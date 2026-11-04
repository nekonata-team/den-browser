import DenDomain
import Foundation
import WebKit

@MainActor
final class DenAPIBridge: NSObject {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private weak var webView: WKWebView?
    private let focus: (BoardID) throws -> Void
    static let handlerName = "denAPI"
    private let router: DenAPIMessageRouter
    private var isEnabled = false
    private var userScript: WKUserScript?

    init(webView: WKWebView, focus: @escaping (BoardID) throws -> Void) {
        self.webView = webView
        self.focus = focus
        router = DenAPIMessageRouter.shared(for: webView.configuration.userContentController)
        super.init()
        router.owners.setObject(self, forKey: webView)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        guard let controller = webView?.configuration.userContentController else { return }
        let retained = controller.userScripts.filter { $0 !== userScript }
        controller.removeAllUserScripts()
        retained.forEach(controller.addUserScript)
        userScript = nil
        guard enabled else { return }
        let source = """
            (() => {
                const current = new URL(window.location.href);
                if (current.protocol !== 'file:' || (current.hostname !== '' && current.hostname !== 'localhost')
                    || !/\\.html?$/i.test(decodeURIComponent(current.pathname))) return;
                const denAPITransport = window.webkit.messageHandlers.\(Self.handlerName);
                \(Self.sdkSource)
            })();
            """
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page)
        controller.addUserScript(script)
        userScript = script
    }

    func dispose() {
        setEnabled(false)
        if let webView {
            router.owners.removeObject(forKey: webView)
            if router.owners.count == 0 {
                let controller = webView.configuration.userContentController
                controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .page)
                DenAPIMessageRouter.routers.removeObject(forKey: controller)
            }
        }
        webView = nil
    }

    fileprivate func receive(
        _ message: WKScriptMessage,
        replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) {
        guard isEnabled, let webView, message.webView === webView, message.frameInfo.isMainFrame,
            DenAPIPolicy.isLocalHTML(message.frameInfo.request.url),
            DenAPIPolicy.isLocalHTML(webView.url)
        else {
            replyHandler(nil, "Den API is not enabled for this document")
            return
        }
        guard let body = message.body as? [String: Any], body["action"] as? String == "board.focus",
            let rawID = body["boardId"] as? String, let id = UUID(uuidString: rawID)
        else {
            replyHandler(nil, "Expected board.focus with a Board UUID")
            return
        }
        do {
            try focus(BoardID(id))
            replyHandler(NSNull(), nil)
        } catch {
            replyHandler(nil, error.localizedDescription)
        }
    }

    private static let sdkSource: String = {
        guard let url = Bundle(for: DenAPIBridge.self).url(forResource: "DenAPI", withExtension: "js") else {
            preconditionFailure("Bundled DenAPI.js is missing")
        }
        do { return try String(contentsOf: url, encoding: .utf8) } catch {
            preconditionFailure("Could not read bundled DenAPI.js: \(error)")
        }
    }()
}

/// Popups may share a controller; dispatch using the actual sender, never the last registered Board.
@MainActor
private final class DenAPIMessageRouter: NSObject, WKScriptMessageHandlerWithReply {
    static let routers = NSMapTable<WKUserContentController, DenAPIMessageRouter>.weakToWeakObjects()
    let owners = NSMapTable<WKWebView, DenAPIBridge>.weakToWeakObjects()

    static func shared(for controller: WKUserContentController) -> DenAPIMessageRouter {
        if let router = routers.object(forKey: controller) { return router }
        let router = DenAPIMessageRouter()
        routers.setObject(router, forKey: controller)
        controller.addScriptMessageHandler(router, contentWorld: .page, name: DenAPIBridge.handlerName)
        return router
    }

    func userContentController(
        _ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) {
        guard let webView = message.webView, let owner = owners.object(forKey: webView) else {
            replyHandler(nil, "Den API is not enabled for this WebView")
            return
        }
        owner.receive(message, replyHandler: replyHandler)
    }
}
