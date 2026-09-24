import AppKit
import Foundation
import WebKit

enum MouseButton: Int {
    case primary = 0
    case middle = 4
}

struct DownloadActivity: Equatable, Identifiable {
    let id: UUID
    let filename: String
    var fractionCompleted: Double?

    init(id: UUID = UUID(), filename: String, fractionCompleted: Double? = nil) {
        self.id = id
        self.filename = filename
        self.fractionCompleted = fractionCompleted
    }
}

enum DownloadActivityEvent: Equatable {
    case started(DownloadActivity)
    case progressed(id: UUID, fractionCompleted: Double?)
    case ended(id: UUID)
}

@MainActor
class BaseWebRuntime: NSObject, NSWindowDelegate, WKDownloadDelegate, WKNavigationDelegate, WKUIDelegate {
    static var defaultUserAgent: String {
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion)"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/\(versionString) Safari/605.1.15"
    }

    let id: UUID
    let webView: WKWebView

    struct PendingDownload: Equatable {
        let activityID: UUID
        let destinationURL: URL
        let temporaryURL: URL
        var fractionCompleted: Double?

        var activity: DownloadActivity {
            DownloadActivity(
                id: activityID,
                filename: destinationURL.lastPathComponent,
                fractionCompleted: fractionCompleted)
        }
    }

    private var auxiliaryWindows: [ObjectIdentifier: NSWindow] = [:]
    private(set) var pendingDownloads: [ObjectIdentifier: PendingDownload] = [:]
    private var downloadProgressObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    var activeDownloadActivities: [DownloadActivity] {
        pendingDownloads.values.map(\.activity)
    }

    init(
        id: UUID,
        initialURL: URL?,
        websiteDataStore: WKWebsiteDataStore,
        userContentController: WKUserContentController?,
        webExtensionController: WKWebExtensionController? = nil,
        sheetScale: Int,
        enableElementFullscreen: Bool = true,
        existingWebView: WKWebView? = nil,
        makeWebView: ((WKWebViewConfiguration) -> WKWebView)? = nil
    ) {
        self.id = id

        let webView: WKWebView
        if let existingWebView {
            webView = existingWebView
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = websiteDataStore
            if let userContentController {
                configuration.userContentController = userContentController
            }
            configuration.webExtensionController = webExtensionController
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.preferences.isElementFullscreenEnabled = enableElementFullscreen
            webView = makeWebView?(configuration) ?? WKWebView(frame: .zero, configuration: configuration)
        }
        self.webView = webView
        let fallbackColor = DenSurfaceColors.webViewFallbackBackground
        webView.underPageBackgroundColor = NSColor(
            calibratedRed: fallbackColor.red,
            green: fallbackColor.green,
            blue: fallbackColor.blue,
            alpha: 1
        )
        webView.customUserAgent = Self.defaultUserAgent
        if existingWebView == nil {
            webView.pageZoom = CGFloat(sheetScale) / 100
        }
        webView.allowsBackForwardNavigationGestures = true

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self

        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleURLOrTitleChange(url: self.webView.url, title: self.webView.title)
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleURLOrTitleChange(url: self.webView.url, title: self.webView.title)
            }
        }

        if existingWebView == nil, let initialURL {
            load(initialURL)
        }
    }

    @discardableResult
    func load(_ url: URL) -> WKNavigation? {
        webView.loadSheetURL(url)
    }

    func dispose() {
        for window in Array(auxiliaryWindows.values) {
            window.delegate = nil
            window.close()
        }
        auxiliaryWindows.removeAll()
        cleanupAllPendingDownloads()
        webView.closeAllMediaPresentations(completionHandler: nil)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        urlObservation?.invalidate()
        titleObservation?.invalidate()
        urlObservation = nil
        titleObservation = nil
    }

    func cleanupAllPendingDownloads() {
        for key in Array(pendingDownloads.keys) {
            guard let pending = removePendingDownload(for: key) else { continue }
            try? FileManager.default.removeItem(at: pending.temporaryURL)
        }
    }

    // MARK: - Hooks for Subclasses

    func handleURLOrTitleChange(url: URL?, title: String?) {
        // Overridden by subclasses
    }

    func handleLinkNavigation(
        _ url: URL,
        navigationType: WKNavigationType,
        modifierFlags: NSEvent.ModifierFlags,
        button: MouseButton?,
        opensNewContext: Bool
    ) -> Bool {
        // Overridden by subclasses if needed. Return true if handled.
        return false
    }

    func handleLinkActivation(navigationType: WKNavigationType) {
        // Overridden by subclasses when link activation affects Board state.
    }

    func notifyDownloadFinished(filename: String) {
        // Overridden by subclasses
    }

    func notifyDownloadFailed(filename: String) {
        // Overridden by subclasses
    }

    func notifyDownloadActivity(_ event: DownloadActivityEvent) {
        // Overridden by subclasses
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {}

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        if navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .other,
            ExternalURLPolicy.isSupported(url)
        {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        if handleLinkNavigation(
            url,
            navigationType: navigationAction.navigationType,
            modifierFlags: navigationAction.modifierFlags,
            button: MouseButton(rawValue: navigationAction.buttonNumber),
            opensNewContext: navigationAction.targetFrame == nil
        ) {
            decisionHandler(.cancel)
            return
        }

        handleLinkActivation(navigationType: navigationAction.navigationType)
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    // WebKit creates downloads from its macOS context menu outside the public navigation callbacks.
    @objc(_webView:contextMenuDidCreateDownload:)
    func webView(_ webView: WKWebView, contextMenuDidCreate download: WKDownload) {
        download.delegate = self
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
            return nil
        }

        if navigationAction.shouldPerformDownload {
            load(url)
        } else if navigationAction.navigationType == .linkActivated,
            ExternalURLPolicy.isSupported(url)
        {
            NSWorkspace.shared.open(url)
        } else if SheetURLPolicy.isSupported(url) {
            if !handleLinkNavigation(
                url,
                navigationType: navigationAction.navigationType,
                modifierFlags: navigationAction.modifierFlags,
                button: MouseButton(rawValue: navigationAction.buttonNumber),
                opensNewContext: true
            ) {
                handleLinkActivation(navigationType: navigationAction.navigationType)
                return makeAuxiliaryWebView(configuration: configuration, sourceWebView: webView)
            }
        } else {
            return makeAuxiliaryWebView(configuration: configuration, sourceWebView: webView)
        }
        return nil
    }

    func makeAuxiliaryWebView(
        configuration: WKWebViewConfiguration,
        sourceWebView: WKWebView
    ) -> WKWebView {
        let auxiliaryWebView = WKWebView(frame: .zero, configuration: configuration)
        auxiliaryWebView.customUserAgent = Self.defaultUserAgent
        auxiliaryWebView.pageZoom = sourceWebView.pageZoom
        auxiliaryWebView.uiDelegate = self
        auxiliaryWebView.navigationDelegate = self

        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = auxiliaryWebView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        auxiliaryWindows[ObjectIdentifier(auxiliaryWebView)] = window
        return auxiliaryWebView
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Alert"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Confirmation"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let input = NSTextField(string: defaultText ?? "")
        input.frame.size.width = 320

        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Prompt"
        alert.informativeText = prompt
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        completionHandler(
            alert.runModal() == .alertFirstButtonReturn
                ? input.stringValue
                : nil
        )
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        guard let window = webView.window ?? NSApp.keyWindow else {
            completionHandler(nil)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = !parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let window = auxiliaryWindows.removeValue(forKey: ObjectIdentifier(webView)) {
            window.delegate = nil
            window.close()
            return
        }
        handleWebViewDidClose(webView)
    }

    func handleWebViewDidClose(_ webView: WKWebView) {}

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        auxiliaryWindows = auxiliaryWindows.filter { $0.value !== window }
    }

    // MARK: - WKDownloadDelegate

    static func temporaryDownloadURL(for destinationURL: URL) -> URL {
        let directory = destinationURL.deletingLastPathComponent()
        let filename = destinationURL.lastPathComponent
        let uniqueID = UUID().uuidString
        return directory.appending(path: ".\(filename).\(uniqueID).download")
    }

    static func finalizeDownload(from temporaryURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: .withoutDeletingBackupItem
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename

        let complete: @MainActor @Sendable (NSApplication.ModalResponse) -> Void = {
            [weak self] response in
            guard response == .OK, let destination = panel.url else {
                completionHandler(nil)
                return
            }

            let temporaryURL = Self.temporaryDownloadURL(for: destination)
            let key = ObjectIdentifier(download)
            self?.registerPendingDownload(
                for: key,
                destinationURL: destination,
                temporaryURL: temporaryURL
            )
            self?.observeDownloadProgress(download.progress, for: key)
            completionHandler(temporaryURL)
        }

        if let window = webView.window ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    @discardableResult
    func registerPendingDownload(
        for key: ObjectIdentifier,
        destinationURL: URL,
        temporaryURL: URL
    ) -> UUID {
        let activity = DownloadActivity(filename: destinationURL.lastPathComponent)
        pendingDownloads[key] = PendingDownload(
            activityID: activity.id,
            destinationURL: destinationURL,
            temporaryURL: temporaryURL,
            fractionCompleted: nil
        )
        notifyDownloadActivity(.started(activity))
        return activity.id
    }

    @discardableResult
    func completeDownload(for key: ObjectIdentifier) -> Bool {
        guard let pending = removePendingDownload(for: key) else { return false }
        do {
            try Self.finalizeDownload(from: pending.temporaryURL, to: pending.destinationURL)
            notifyDownloadFinished(filename: pending.destinationURL.lastPathComponent)
            return true
        } catch {
            try? FileManager.default.removeItem(at: pending.temporaryURL)
            notifyDownloadFailed(filename: pending.destinationURL.lastPathComponent)
            return false
        }
    }

    func failDownload(for key: ObjectIdentifier) {
        guard let pending = removePendingDownload(for: key) else { return }
        try? FileManager.default.removeItem(at: pending.temporaryURL)
        notifyDownloadFailed(filename: pending.destinationURL.lastPathComponent)
    }

    nonisolated static func downloadProgressFraction(_ progress: Progress) -> Double? {
        let fraction = progress.fractionCompleted
        guard !progress.isIndeterminate, fraction.isFinite else { return nil }
        return min(max(fraction, 0), 1)
    }

    private func observeDownloadProgress(_ progress: Progress, for key: ObjectIdentifier) {
        downloadProgressObservations[key] = progress.observe(
            \.fractionCompleted,
            options: [.initial, .new]
        ) { [weak self] progress, _ in
            let fractionCompleted = Self.downloadProgressFraction(progress)
            Task { @MainActor [weak self] in
                self?.updateDownloadProgress(for: key, fractionCompleted: fractionCompleted)
            }
        }
    }

    private func updateDownloadProgress(for key: ObjectIdentifier, fractionCompleted: Double?) {
        guard var pending = pendingDownloads[key] else { return }
        pending.fractionCompleted = fractionCompleted
        pendingDownloads[key] = pending
        notifyDownloadActivity(
            .progressed(id: pending.activityID, fractionCompleted: fractionCompleted))
    }

    private func removePendingDownload(for key: ObjectIdentifier) -> PendingDownload? {
        downloadProgressObservations.removeValue(forKey: key)?.invalidate()
        guard let pending = pendingDownloads.removeValue(forKey: key) else { return nil }
        notifyDownloadActivity(.ended(id: pending.activityID))
        return pending
    }

    func downloadDidFinish(_ download: WKDownload) {
        completeDownload(for: ObjectIdentifier(download))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        failDownload(for: ObjectIdentifier(download))
    }
}
