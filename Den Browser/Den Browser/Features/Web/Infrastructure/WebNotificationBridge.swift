import Foundation
import WebKit

@MainActor
final class WebNotificationBridge: NSObject {
    static let handlerName = "denWebNotification"

    private weak var webView: WKWebView?
    private let router: WebNotificationMessageRouter
    private let onNotification: (String?, String) -> Void

    init(
        webView: WKWebView,
        onNotification: @escaping (String?, String) -> Void
    ) {
        self.webView = webView
        self.onNotification = onNotification
        let controller = webView.configuration.userContentController
        Self.installScriptIfNeeded(on: controller)
        router = WebNotificationMessageRouter.shared(for: controller)
        super.init()
        router.owners.setObject(self, forKey: webView)
    }

    func dispose() {
        if let webView {
            router.owners.removeObject(forKey: webView)
            if router.owners.count == 0 {
                let controller = webView.configuration.userContentController
                controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .page)
                WebNotificationMessageRouter.routers.removeObject(forKey: controller)
            }
        }
        webView = nil
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard let webView, message.webView === webView,
            let payload = message.body as? [String: Any]
        else { return }
        let title = payload["title"] as? String
        let body = payload["body"] as? String ?? ""
        onNotification(title, body)
    }

    private static func installScriptIfNeeded(on controller: WKUserContentController) {
        guard !scriptSource.isEmpty,
            !controller.userScripts.contains(where: { $0.source == scriptSource })
        else { return }
        controller.addUserScript(
            WKUserScript(
                source: scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            )
        )
    }

    private static let scriptSource: String = {
        let bundles: [Bundle] = [
            Bundle.main,
            Bundle(for: WebNotificationBundleToken.self),
            Bundle(identifier: "dev.nekonata.denbrowser"),
        ].compactMap { $0 }
        for bundle in bundles {
            guard
                let url = bundle.url(forResource: "WebNotification", withExtension: "js"),
                let source = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            return source
        }
        return ""
    }()
}

@MainActor
private final class WebNotificationMessageRouter: NSObject, WKScriptMessageHandler {
    static let routers = NSMapTable<WKUserContentController, WebNotificationMessageRouter>.weakToStrongObjects()
    let owners = NSMapTable<WKWebView, WebNotificationBridge>.weakToWeakObjects()

    static func shared(for controller: WKUserContentController) -> WebNotificationMessageRouter {
        if let existing = routers.object(forKey: controller) {
            return existing
        }
        let router = WebNotificationMessageRouter()
        routers.setObject(router, forKey: controller)
        controller.add(router, contentWorld: .page, name: WebNotificationBridge.handlerName)
        return router
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let webView = message.webView, let owner = owners.object(forKey: webView) else {
            return
        }
        owner.receive(message)
    }
}

private final class WebNotificationBundleToken: NSObject {}
