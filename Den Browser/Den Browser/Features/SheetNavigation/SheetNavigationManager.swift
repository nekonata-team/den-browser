import AppKit
import Foundation
import Observation
import WebKit

@MainActor
private final class SheetNavigationMessageHandler: NSObject, WKScriptMessageHandler {
    var onMessage: ((WKScriptMessage) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        onMessage?(message)
    }
}

@MainActor
@Observable
final class SheetNavigationManager {
    struct Actions {
        var onOpenBoard: (URL) -> Void = { _ in }
        var onOpenBoardInBackground: (URL) -> Void = { _ in }
        var onKeepInDrawer: (URL) -> Void = { _ in }
        var onEditCurrentSheet: () -> Void = {}
        var onOpenCurrentSheetInNewBoard: (URL) -> Void = { _ in }
        var onPasteURLInNewBoard: (URL) -> Void = { _ in }
        var onCopyURLSucceeded: () -> Void = {}
        var onCopyURLFailed: () -> Void = {}
        var onCopyMarkdownLinkSucceeded: () -> Void = {}
        var onCopyMarkdownLinkFailed: () -> Void = {}
        var onPasteURLFailed: () -> Void = {}
        var onOpenBoardPanel: () -> Void = {}
        var onShowOverview: () -> Void = {}
        var onShowEssentials: () -> Void = {}
        var onRemoveBoard: () -> Void = {}
        var onRemoveBoardAndFocusNext: () -> Void = {}
        var onRestoreBoard: () -> Void = {}
        var onFocusFirstBoard: () -> Void = {}
        var onFocusLastBoard: () -> Void = {}
        var onFocusPreviousBoard: () -> Void = {}
        var onFocusNextBoard: () -> Void = {}
        var onGoToFirstSheet: () -> Void = {}
        var onGoToLatestSheet: () -> Void = {}
        var isSupportedSheetURL: (URL) -> Bool = { _ in false }
        var onNavigateCurrentSheet: (URL) -> Void = { _ in }
    }

    static let defaultHintAlphabet = "asdfghjkl"
    static let contentWorld = WKContentWorld.world(name: "dev.nekonata.denbrowser.sheet-navigation")

    let userContentController = WKUserContentController()
    private(set) var isEnabled: Bool
    private(set) var hintAlphabet: String
    private(set) var ignoredHosts: [String]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let scriptSource: String
    @ObservationIgnored private let webViews = NSHashTable<WKWebView>.weakObjects()
    @ObservationIgnored private let messageHandler = SheetNavigationMessageHandler()
    @ObservationIgnored private var actionsByWebView: [ObjectIdentifier: Actions] = [:]
    @ObservationIgnored private var boardIDByWebView: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private var pausedByWebView: [ObjectIdentifier: Bool] = [:]

    init(
        defaults: UserDefaults = .standard,
        scriptSource: String? = nil
    ) {
        self.defaults = defaults
        self.scriptSource = scriptSource ?? Self.bundledScript
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        hintAlphabet =
            Self.normalizeHintAlphabet(defaults.string(forKey: Self.hintAlphabetKey) ?? "")
            ?? Self.defaultHintAlphabet
        ignoredHosts = defaults.stringArray(forKey: Self.ignoredHostsKey) ?? []
        configureMessageHandler()
    }

    private func configureMessageHandler() {
        messageHandler.onMessage = { [weak self] message in
            self?.handleScriptMessage(message)
        }
        userContentController.add(
            messageHandler,
            contentWorld: Self.contentWorld,
            name: "denSheetNavigation"
        )
        installStartupScript()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        applyConfiguration()
    }

    @discardableResult
    func setHintAlphabet(_ alphabet: String) -> Bool {
        guard let normalized = Self.normalizeHintAlphabet(alphabet) else { return false }
        guard normalized != hintAlphabet else { return true }
        hintAlphabet = normalized
        defaults.set(normalized, forKey: Self.hintAlphabetKey)
        applyConfiguration()
        return true
    }

    @discardableResult
    func setIgnoredSites(_ sites: String) -> Bool {
        guard let hosts = Self.normalizeIgnoredSites(sites) else { return false }
        guard hosts != ignoredHosts else { return true }
        ignoredHosts = hosts
        defaults.set(hosts, forKey: Self.ignoredHostsKey)
        applyConfiguration()
        return true
    }

    func didOpen(
        _ webView: WKWebView,
        boardID: UUID? = nil,
        paused: Bool = false,
        actions: Actions
    ) {
        let webViewID = ObjectIdentifier(webView)
        webViews.add(webView)
        actionsByWebView[webViewID] = actions
        if let boardID { boardIDByWebView[webViewID] = boardID }
        pausedByWebView[webViewID] = paused
        applyConfiguration(to: webView)
    }

    func didClose(_ webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        webViews.remove(webView)
        actionsByWebView.removeValue(forKey: webViewID)
        boardIDByWebView.removeValue(forKey: webViewID)
        pausedByWebView.removeValue(forKey: webViewID)
    }

    func updateActions(_ actions: Actions, for webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard actionsByWebView[webViewID] != nil else { return }
        actionsByWebView[webViewID] = actions
    }

    func refreshConfiguration(for webView: WKWebView) {
        applyConfiguration(to: webView)
    }

    func setBoardPaused(_ paused: Bool, for boardID: UUID) {
        for webView in webViews.allObjects where boardIDByWebView[ObjectIdentifier(webView)] == boardID {
            let webViewID = ObjectIdentifier(webView)
            guard pausedByWebView[webViewID] != paused else { continue }
            pausedByWebView[webViewID] = paused
            applyConfiguration(to: webView)
        }
    }

    static func normalizeHintAlphabet(_ alphabet: String) -> String? {
        var result = ""
        var seen: Set<Character> = []

        for scalar in alphabet.unicodeScalars {
            let value = scalar.value
            guard (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value) else {
                return nil
            }
            let character = Character(String(scalar).lowercased())
            if seen.insert(character).inserted {
                result.append(character)
            }
        }

        return result.count >= 2 ? result : nil
    }

    static func normalizeIgnoredSites(_ sites: String) -> [String]? {
        var hosts: [String] = []
        var seen: Set<String> = []

        for line in sites.split(whereSeparator: \Character.isNewline) {
            let value = line.trimmingCharacters(in: .whitespaces)
            guard
                !value.isEmpty,
                let url = URL(string: value.contains("://") ? value : "https://\(value)"),
                var host = url.host(percentEncoded: false)?.lowercased()
            else { return nil }
            host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !host.isEmpty else { return nil }
            if seen.insert(host).inserted {
                hosts.append(host)
            }
        }

        return hosts
    }

    @discardableResult
    func handleScriptMessage(_ body: Any, from webView: WKWebView) -> Bool {
        guard
            let message = body as? [String: Any],
            let action = message["action"] as? String
        else { return false }

        guard
            action == "commandOpenBoard"
                || action == "keepInDrawer"
                || (isEnabled && !isIgnored(webView.url))
        else {
            return false
        }

        switch action {
        case "copyURL":
            guard let actions = actionsByWebView[ObjectIdentifier(webView)] else { return false }
            guard let url = webView.url else {
                actions.onCopyURLFailed()
                return false
            }
            NSPasteboard.general.clearContents()
            let copied = NSPasteboard.general.setString(url.absoluteString, forType: .string)
            if copied {
                actions.onCopyURLSucceeded()
            } else {
                actions.onCopyURLFailed()
            }
            return copied
        case "copyMarkdownLink":
            guard let actions = actionsByWebView[ObjectIdentifier(webView)] else { return false }
            guard let url = webView.url else {
                actions.onCopyMarkdownLinkFailed()
                return false
            }
            let rawTitle = (message["title"] as? String) ?? webView.title ?? ""
            let markdown = Self.markdownLink(title: rawTitle, url: url)
            NSPasteboard.general.clearContents()
            let copied = NSPasteboard.general.setString(markdown, forType: .string)
            if copied {
                actions.onCopyMarkdownLinkSucceeded()
            } else {
                actions.onCopyMarkdownLinkFailed()
            }
            return copied
        case "openBoard", "commandOpenBoard":
            guard
                let urlString = message["url"] as? String,
                let url = URL(string: urlString),
                let actions = actionsByWebView[ObjectIdentifier(webView)],
                actions.isSupportedSheetURL(url)
            else { return false }
            if action == "commandOpenBoard",
                message["focused"] as? Bool != true
            {
                actions.onOpenBoardInBackground(url)
            } else {
                actions.onOpenBoard(url)
            }
            return true
        case "keepInDrawer":
            guard
                let urlString = message["url"] as? String,
                let url = URL(string: urlString),
                let actions = actionsByWebView[ObjectIdentifier(webView)],
                actions.isSupportedSheetURL(url)
            else { return false }
            actions.onKeepInDrawer(url)
            return true
        case "editCurrentSheet":
            guard
                let url = webView.url,
                let actions = actionsByWebView[ObjectIdentifier(webView)],
                actions.isSupportedSheetURL(url)
            else { return false }
            actions.onEditCurrentSheet()
            return true
        case "openCurrentSheetInNewBoard":
            guard
                let url = webView.url,
                let actions = actionsByWebView[ObjectIdentifier(webView)],
                actions.isSupportedSheetURL(url)
            else { return false }
            actions.onOpenCurrentSheetInNewBoard(url)
            return true
        case "openBoardPanel":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onOpenBoardPanel else {
                return false
            }
            action()
            return true
        case "showOverview":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onShowOverview else {
                return false
            }
            action()
            return true
        case "showEssentials":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onShowEssentials else {
                return false
            }
            action()
            return true
        case "pasteURL", "pasteURLInNewBoard":
            guard let actions = actionsByWebView[ObjectIdentifier(webView)] else { return false }
            let value = NSPasteboard.general.string(forType: .string)
                .map { SheetURLPolicy.normalizePastedText($0, joiningLineBreaksWith: "") }
            guard
                let value,
                let url = URL(string: value),
                actions.isSupportedSheetURL(url)
            else {
                actions.onPasteURLFailed()
                return false
            }
            if action == "pasteURL" {
                actions.onNavigateCurrentSheet(url)
            } else {
                actions.onPasteURLInNewBoard(url)
            }
            return true
        case "removeBoard":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onRemoveBoard else { return false }
            action()
            return true
        case "removeBoardAndFocusNext":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onRemoveBoardAndFocusNext else {
                return false
            }
            action()
            return true
        case "restoreBoard":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onRestoreBoard else { return false }
            action()
            return true
        case "focusFirstBoard":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onFocusFirstBoard else {
                return false
            }
            action()
            return true
        case "focusLastBoard":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onFocusLastBoard else {
                return false
            }
            action()
            return true
        case "focusPreviousBoard":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onFocusPreviousBoard else {
                return false
            }
            action()
            return true
        case "focusNextBoard":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onFocusNextBoard else {
                return false
            }
            action()
            return true
        case "goToFirstSheet":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onGoToFirstSheet else {
                return false
            }
            action()
            return true
        case "goToLatestSheet":
            guard let action = actionsByWebView[ObjectIdentifier(webView)]?.onGoToLatestSheet else {
                return false
            }
            action()
            return true
        default:
            return false
        }
    }

    private func handleScriptMessage(_ message: WKScriptMessage) {
        guard
            message.frameInfo.isMainFrame,
            message.world === Self.contentWorld,
            let webView = message.webView
        else { return }
        handleScriptMessage(message.body, from: webView)
    }

    private func isIgnored(_ url: URL?) -> Bool {
        guard let hostname = url?.host(percentEncoded: false)?.lowercased() else { return false }
        return ignoredHosts.contains { hostname == $0 || hostname.hasSuffix(".\($0)") }
    }

    private func applyConfiguration() {
        installStartupScript()
        for webView in webViews.allObjects {
            applyConfiguration(to: webView)
        }
    }

    private func applyConfiguration(to webView: WKWebView) {
        webView.evaluateJavaScript(
            configurationJavaScript(for: webView), in: nil, in: Self.contentWorld, completionHandler: nil)
    }

    private func installStartupScript() {
        userContentController.removeAllUserScripts()
        userContentController.addUserScript(
            WKUserScript(
                source: scriptSource + "\n" + configurationJavaScript(for: nil),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: Self.contentWorld
            ))
    }

    private func configurationJavaScript(for webView: WKWebView?) -> String {
        let configuration: [String: Any] = [
            "enabled": isEnabled,
            "alphabet": hintAlphabet,
            "ignoredHosts": ignoredHosts,
            "paused": webView.map { pausedByWebView[ObjectIdentifier($0)] ?? false } ?? false,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: configuration) else {
            return ""
        }
        guard let configurationScript = String(data: data, encoding: .utf8) else {
            return ""
        }
        return "window.__denSheetNavigation?.configure(\(configurationScript));"
    }

    private static let bundledScript: String = {
        guard
            let url = Bundle.main.url(forResource: "SheetNavigation", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()

    static func markdownLink(title: String, url: URL) -> String {
        let collapsedTitle =
            title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let sanitizedTitle = collapsedTitle.isEmpty ? url.absoluteString : collapsedTitle
        let escapedTitle =
            sanitizedTitle
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "[\(escapedTitle)](\(url.absoluteString))"
    }

    static let enabledKey = "preferences.sheet-navigation.enabled"
    private static let hintAlphabetKey = "preferences.sheet-navigation.hint-alphabet"
    private static let ignoredHostsKey = "preferences.sheet-navigation.ignored-hosts"
}
