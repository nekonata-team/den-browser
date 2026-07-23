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
    @ObservationIgnored private var openBoardCallbacks: [ObjectIdentifier: (URL) -> Void] = [:]

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

    func didOpen(_ webView: WKWebView, onOpenBoard: @escaping (URL) -> Void) {
        webViews.add(webView)
        openBoardCallbacks[ObjectIdentifier(webView)] = onOpenBoard
    }

    func didClose(_ webView: WKWebView) {
        webViews.remove(webView)
        openBoardCallbacks.removeValue(forKey: ObjectIdentifier(webView))
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
            isEnabled,
            !isIgnored(webView.url),
            let message = body as? [String: Any],
            let action = message["action"] as? String
        else { return false }

        switch action {
        case "copyURL":
            guard let url = webView.url else { return false }
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(url.absoluteString, forType: .string)
        case "openBoard":
            guard
                let urlString = message["url"] as? String,
                let url = URL(string: urlString),
                Self.isSupported(url),
                let onOpenBoard = openBoardCallbacks[ObjectIdentifier(webView)]
            else { return false }
            onOpenBoard(url)
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

    private static func isSupported(_ url: URL) -> Bool {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host,
            !host.isEmpty
        else { return false }
        return true
    }

    private func applyConfiguration() {
        installStartupScript()
        let javaScript = configurationJavaScript()
        for webView in webViews.allObjects {
            webView.evaluateJavaScript(
                javaScript,
                in: nil,
                in: Self.contentWorld,
                completionHandler: nil
            )
        }
    }

    private func installStartupScript() {
        userContentController.removeAllUserScripts()
        userContentController.addUserScript(
            WKUserScript(
                source: scriptSource + "\n" + configurationJavaScript(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: Self.contentWorld
            ))
    }

    private func configurationJavaScript() -> String {
        let configuration: [String: Any] = [
            "enabled": isEnabled,
            "alphabet": hintAlphabet,
            "ignoredHosts": ignoredHosts,
        ]
        let data = try! JSONSerialization.data(withJSONObject: configuration)
        return "window.__denSheetNavigation?.configure(\(String(decoding: data, as: UTF8.self)));"
    }

    private static let bundledScript: String = {
        guard
            let url = Bundle.main.url(forResource: "SheetNavigation", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()

    private static let enabledKey = "features.vim-style-sheet-navigation.enabled"
    private static let hintAlphabetKey = "features.vim-style-sheet-navigation.hint-alphabet"
    private static let ignoredHostsKey = "features.vim-style-sheet-navigation.ignored-hosts"
}
