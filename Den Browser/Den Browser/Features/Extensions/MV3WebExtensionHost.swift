import AppKit
import Foundation
import WebKit

/// An extension that is shipped with Den Browser.
///
/// Extensions are deliberately described by the app instead of being installed from
/// arbitrary paths. This keeps the first host surface small and makes the set of
/// code that runs in a Profile auditable.
struct WebExtensionDescriptor: Equatable {
    let identifier: String
    let directoryURL: URL?
    let resourceName: String?
    let resourceSubdirectory: String?
    let preapproveRequestedAccess: Bool

    init(
        identifier: String,
        directoryURL: URL,
        preapproveRequestedAccess: Bool = false
    ) {
        self.identifier = identifier
        self.directoryURL = directoryURL
        self.resourceName = nil
        self.resourceSubdirectory = nil
        self.preapproveRequestedAccess = preapproveRequestedAccess
    }

    init(
        identifier: String,
        resourceName: String,
        resourceSubdirectory: String? = nil,
        preapproveRequestedAccess: Bool = false
    ) {
        self.identifier = identifier
        self.directoryURL = nil
        self.resourceName = resourceName
        self.resourceSubdirectory = resourceSubdirectory
        self.preapproveRequestedAccess = preapproveRequestedAccess
    }

    func resourceURL(in bundle: Bundle = .main) -> URL? {
        if let directoryURL {
            return FileManager.default.fileExists(atPath: directoryURL.path) ? directoryURL : nil
        }
        guard let resourceName else { return nil }
        return bundle.url(
            forResource: resourceName,
            withExtension: nil,
            subdirectory: resourceSubdirectory)
    }
}

typealias BundledWebExtensionDescriptor = WebExtensionDescriptor

@MainActor
protocol WebExtensionHost: AnyObject {
    var controller: WKWebExtensionController { get }

    func register(
        webView: WKWebView,
        in window: MV3WebExtensionWindow,
        initialURL: URL?,
        loadURL: @escaping (URL) -> Void
    )
    func activate(webView: WKWebView)
    func unregister(webView: WKWebView)
}

/// Owns WebKit's MV3 runtime for one Profile.
///
/// A controller is intentionally not shared between Profiles. WebKit stores
/// extension data (including `storage.local` and `storage.session`) per controller
/// configuration, while the controller's default website data store provides the
/// Profile's cookie boundary. `storage.sync` remains outside the host's initial
/// compatibility surface and is exposed as unavailable to extensions.
@MainActor
final class MV3WebExtensionHost: NSObject, WKWebExtensionControllerDelegate, WebExtensionHost {
    let controller: WKWebExtensionController

    private let bundle: Bundle
    private let descriptors: [BundledWebExtensionDescriptor]
    private var contexts: [String: WKWebExtensionContext] = [:]
    private var windows: [UUID: MV3WebExtensionWindow] = [:]
    private var tabs: [ObjectIdentifier: MV3WebExtensionTab] = [:]
    private var pendingInitialLoads: [ObjectIdentifier: URL] = [:]
    private var pendingOptionsPageRequest = false
    private var remainingExtensionLoads: Int
    private var isReady: Bool
    private var focusedWindowID: UUID?
    private weak var popupPresentationWindow: NSWindow?
    private weak var popupPresentationView: NSView?
    private weak var pendingActionPopupWindow: NSWindow?
    private var optionsWindow: NSWindow?
    private var isDisposed = false

    init(
        profileID: UUID,
        websiteDataStore: WKWebsiteDataStore,
        userContentController: WKUserContentController,
        descriptors: [BundledWebExtensionDescriptor] = [],
        bundle: Bundle = .main
    ) {
        self.bundle = bundle
        self.descriptors = descriptors
        remainingExtensionLoads = descriptors.count
        isReady = descriptors.isEmpty

        let configuration = WKWebExtensionController.Configuration(identifier: profileID)
        configuration.defaultWebsiteDataStore = websiteDataStore
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.websiteDataStore = websiteDataStore
        webViewConfiguration.userContentController = userContentController
        configuration.webViewConfiguration = webViewConfiguration
        controller = WKWebExtensionController(configuration: configuration)

        super.init()
        controller.delegate = self
        loadBundledExtensions()
    }

    func window(for windowID: UUID) -> MV3WebExtensionWindow {
        if let window = windows[windowID] {
            return window
        }
        let window = MV3WebExtensionWindow(id: windowID)
        windows[windowID] = window
        controller.didOpenWindow(window)
        focusWindow(window)
        return window
    }

    func closeWindow(_ window: MV3WebExtensionWindow) {
        guard windows.removeValue(forKey: window.id) != nil else { return }
        for tab in window.tabs {
            unregister(tab: tab)
        }
        controller.didCloseWindow(window)
        if focusedWindowID == window.id {
            focusWindow(windows.values.first)
        }
    }

    func closeWindow(id: UUID) {
        guard let window = windows[id] else { return }
        closeWindow(window)
    }

    func register(
        webView: WKWebView,
        in window: MV3WebExtensionWindow,
        initialURL: URL?,
        loadURL: @escaping (URL) -> Void
    ) {
        let key = ObjectIdentifier(webView)
        if let existingTab = tabs[key] {
            guard existingTab.window !== window else { return }
            unregister(tab: existingTab)
        }
        let tab = MV3WebExtensionTab(
            webView: webView,
            window: window,
            loadInitialURL: loadURL)
        tabs[key] = tab
        window.add(tab)
        controller.didOpenTab(tab)
        if window.activeTab === tab {
            activate(tab)
        }
        loadInitialURL(initialURL, for: webView)
        presentPendingActionPopupIfPossible()
    }

    func focusWindow(_ window: MV3WebExtensionWindow?) {
        focusedWindowID = window?.id
        controller.didFocusWindow(window)
    }

    func presentActionPopup(from window: NSWindow? = nil, anchorView: NSView? = nil) {
        popupPresentationWindow = window ?? anchorView?.window ?? NSApp.keyWindow
        popupPresentationView = anchorView
        pendingActionPopupWindow = popupPresentationWindow
        presentPendingActionPopupIfPossible()
    }

    func presentOptionsPage() {
        guard !isDisposed else { return }
        if let context = contexts.values.first {
            _ = presentOptionsPage(for: context)
        } else if !isReady {
            pendingOptionsPageRequest = true
        }
    }

    func activate(webView: WKWebView) {
        guard let tab = tabs[ObjectIdentifier(webView)] else { return }
        activate(tab)
    }

    func unregister(webView: WKWebView) {
        guard let tab = tabs[ObjectIdentifier(webView)] else { return }
        unregister(tab: tab)
    }

    private func loadInitialURL(_ url: URL?, for webView: WKWebView) {
        guard let url else { return }
        let key = ObjectIdentifier(webView)
        guard !isDisposed else { return }
        if isReady {
            tabs[key]?.loadInitialURL(url)
        } else {
            pendingInitialLoads[key] = url
        }
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        for context in contexts.values {
            try? controller.unload(context)
        }
        contexts.removeAll()
        for window in windows.values {
            for tab in window.tabs {
                controller.didCloseTab(tab)
            }
            controller.didCloseWindow(window)
        }
        windows.removeAll()
        tabs.removeAll()
        pendingInitialLoads.removeAll()
        pendingOptionsPageRequest = false
        optionsWindow?.close()
        optionsWindow = nil
        popupPresentationWindow = nil
        popupPresentationView = nil
        pendingActionPopupWindow = nil
        controller.delegate = nil
    }

    private func unregister(tab: MV3WebExtensionTab) {
        guard let key = tabs.first(where: { $0.value === tab })?.key else { return }
        let previousTab = tab.window?.activeTab
        tabs.removeValue(forKey: key)
        pendingInitialLoads.removeValue(forKey: key)
        tab.window?.remove(tab)
        controller.didCloseTab(tab)
        if let activeTab = tab.window?.activeTab, previousTab === tab {
            controller.didActivateTab(activeTab, previousActiveTab: tab)
        }
    }

    private func activate(_ tab: MV3WebExtensionTab) {
        let previousTab = tab.window?.activeTab
        tab.window?.activate(tab)
        guard previousTab !== tab else { return }
        controller.didActivateTab(tab, previousActiveTab: previousTab)
    }

    private func loadBundledExtensions() {
        for descriptor in descriptors {
            guard let resourceURL = descriptor.resourceURL(in: bundle) else {
                assertionFailure("WebExtension resource not found: \(descriptor.identifier)")
                extensionLoadFinished()
                continue
            }
            Task { [weak self] in
                guard let self else { return }
                defer { extensionLoadFinished() }
                do {
                    let webExtension = try await WKWebExtension(resourceBaseURL: resourceURL)
                    guard !isDisposed else { return }
                    let context = WKWebExtensionContext(for: webExtension)
                    context.uniqueIdentifier = descriptor.identifier + "." + profileIDSuffix
                    context.unsupportedAPIs = ["browser.storage.sync"]
                    if descriptor.preapproveRequestedAccess {
                        let expirationDate = Date.distantFuture
                        context.grantedPermissions = Dictionary(
                            uniqueKeysWithValues: webExtension.requestedPermissions.map {
                                ($0, expirationDate)
                            })
                        context.grantedPermissionMatchPatterns = Dictionary(
                            uniqueKeysWithValues: webExtension.requestedPermissionMatchPatterns.map {
                                ($0, expirationDate)
                            })
                    }
                    do {
                        try controller.load(context)
                    } catch {
                        reportLoadFailure(descriptor: descriptor, error: error)
                        return
                    }
                    contexts[descriptor.identifier] = context
                } catch {
                    reportLoadFailure(descriptor: descriptor, error: error)
                }
            }
        }
    }

    private func extensionLoadFinished() {
        guard !isDisposed, !isReady else { return }
        remainingExtensionLoads -= 1
        guard remainingExtensionLoads == 0 else { return }
        isReady = true

        let pendingLoads = pendingInitialLoads
        pendingInitialLoads.removeAll()
        for (key, url) in pendingLoads {
            tabs[key]?.loadInitialURL(url)
        }
        if pendingOptionsPageRequest {
            pendingOptionsPageRequest = false
            if let context = contexts.values.first {
                _ = presentOptionsPage(for: context)
            }
        }
        presentPendingActionPopupIfPossible()
    }

    private var profileIDSuffix: String {
        controller.configuration.identifier?.uuidString ?? "default"
    }

    private func reportLoadFailure(descriptor: BundledWebExtensionDescriptor, error: Error?) {
        #if DEBUG
            let detail = error?.localizedDescription ?? "unknown error"
            print("[DenBrowser] Could not load WebExtension \(descriptor.identifier): \(detail)")
        #endif
    }

    private func reportPresentationFailure(_ detail: String) {
        #if DEBUG
            print("[DenBrowser] Could not present WebExtension UI: \(detail)")
        #endif
    }

    private func extensionPresentationError(_ detail: String) -> NSError {
        NSError(
            domain: "DenBrowser.WebExtension",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: detail]
        )
    }

    private func presentOptionsPage(for context: WKWebExtensionContext) -> Error? {
        guard let optionsURL = context.optionsPageURL else {
            return extensionPresentationError("The WebExtension does not declare an options page")
        }
        if let optionsWindow, optionsWindow.isVisible {
            optionsWindow.makeKeyAndOrderFront(nil)
            return nil
        }

        let configuration = context.webViewConfiguration ?? WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.autoresizingMask = [.width, .height]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "uBlock Origin Lite Settings"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        optionsWindow = window
        webView.load(URLRequest(url: optionsURL))
        return nil
    }

    private func presentPendingActionPopupIfPossible() {
        guard isReady,
            let context = contexts.values.first,
            pendingActionPopupWindow != nil
        else { return }
        pendingActionPopupWindow = nil
        let extensionWindow = focusedWindowID.flatMap({ windows[$0] }) ?? windows.values.first
        let tab = extensionWindow?.activeTab
        context.performAction(for: tab)
    }

    // MARK: WKWebExtensionControllerDelegate

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        windows.values.sorted { lhs, rhs in
            lhs.id == focusedWindowID && rhs.id != focusedWindowID
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        focusedWindowID.flatMap { windows[$0] }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let popover = action.popupPopover else {
            let error = extensionPresentationError("The WebExtension action does not declare a popup")
            reportPresentationFailure(error.localizedDescription)
            completionHandler(error)
            return
        }
        guard let anchorWindow = popupPresentationWindow ?? NSApp.keyWindow,
            let fallbackAnchorView = anchorWindow.contentView
        else {
            let error = extensionPresentationError("No window is available for the WebExtension popup")
            reportPresentationFailure(error.localizedDescription)
            completionHandler(error)
            return
        }

        if popover.isShown {
            popover.close()
        } else {
            popover.behavior = .transient
            if let popupPresentationView,
                let popupWindow = popupPresentationView.window,
                let contentView = popupWindow.contentView
            {
                let anchorBounds = popupPresentationView.bounds
                let localAnchorRect =
                    anchorBounds.isEmpty
                    ? NSRect(
                        x: anchorBounds.midX,
                        y: anchorBounds.midY,
                        width: 1,
                        height: 1)
                    : anchorBounds
                let anchorRect = popupPresentationView.convert(
                    localAnchorRect,
                    to: contentView)
                popover.show(
                    relativeTo: anchorRect,
                    of: contentView,
                    preferredEdge: .maxY)
            } else {
                let anchorRect = NSRect(
                    x: fallbackAnchorView.bounds.midX,
                    y: fallbackAnchorView.bounds.midY,
                    width: 1,
                    height: 1)
                popover.show(
                    relativeTo: anchorRect,
                    of: fallbackAnchorView,
                    preferredEdge: .maxY)
            }
        }
        completionHandler(nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let error = presentOptionsPage(for: extensionContext)
        if let error {
            reportPresentationFailure(error.localizedDescription)
        }
        completionHandler(error)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        completionHandler([], nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        completionHandler([], nil)
    }
}

@MainActor
final class MV3WebExtensionWindow: NSObject, WKWebExtensionWindow {
    let id: UUID
    private(set) var tabs: [MV3WebExtensionTab] = []
    private(set) var activeTab: MV3WebExtensionTab?

    init(id: UUID) {
        self.id = id
        super.init()
    }

    func add(_ tab: MV3WebExtensionTab) {
        tabs.append(tab)
        activeTab = activeTab ?? tab
    }

    func remove(_ tab: MV3WebExtensionTab) {
        tabs.removeAll { $0 === tab }
        if activeTab === tab {
            activeTab = tabs.last
        }
    }

    func activate(_ tab: MV3WebExtensionTab) {
        guard tabs.contains(where: { $0 === tab }) else { return }
        activeTab = tab
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        tabs
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        activeTab
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        .normal
    }
}

@MainActor
final class MV3WebExtensionTab: NSObject, WKWebExtensionTab {
    weak var webView: WKWebView?
    weak var window: MV3WebExtensionWindow?
    private let loadInitialURLHandler: (URL) -> Void

    init(
        webView: WKWebView,
        window: MV3WebExtensionWindow,
        loadInitialURL: @escaping (URL) -> Void
    ) {
        self.webView = webView
        self.window = window
        self.loadInitialURLHandler = loadInitialURL
        super.init()
    }

    func loadInitialURL(_ url: URL) {
        loadInitialURLHandler(url)
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        window
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        window?.tabs.firstIndex { $0 === self } ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        webView
    }

    func title(for context: WKWebExtensionContext) -> String? {
        webView?.title
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        webView?.url
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        !(webView?.isLoading ?? false)
    }

    func loadURL(
        _ url: URL,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        webView?.load(URLRequest(url: url))
        completionHandler(nil)
    }

    func reload(
        fromOrigin: Bool,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if fromOrigin {
            webView?.reloadFromOrigin()
        } else {
            webView?.reload()
        }
        completionHandler(nil)
    }

    func goBack(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        webView?.goBack()
        completionHandler(nil)
    }

    func goForward(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        webView?.goForward()
        completionHandler(nil)
    }

    func activate(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        window?.activate(self)
        completionHandler(nil)
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        window?.activeTab === self
    }
}
