import Foundation
import WebKit

@MainActor
final class PictureInPictureStateBridge: NSObject {
    static let handlerName = "denPictureInPictureState"

    private weak var webView: WKWebView?
    private let router: PictureInPictureStateMessageRouter
    private let onStateChange: (Bool) -> Void

    init(
        webView: WKWebView,
        onStateChange: @escaping (Bool) -> Void
    ) {
        self.webView = webView
        self.onStateChange = onStateChange
        let controller = webView.configuration.userContentController
        Self.installScriptIfNeeded(on: controller)
        router = PictureInPictureStateMessageRouter.shared(for: controller)
        super.init()
        router.owners.setObject(self, forKey: webView)
    }

    func dispose() {
        if let webView {
            router.owners.removeObject(forKey: webView)
            if router.owners.count == 0 {
                let controller = webView.configuration.userContentController
                controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .defaultClient)
                PictureInPictureStateMessageRouter.routers.removeObject(forKey: controller)
            }
        }
        webView = nil
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard let webView, message.webView === webView,
            let payload = message.body as? [String: Any],
            let active = payload["active"] as? Bool
        else { return }
        onStateChange(active)
    }

    private static func installScriptIfNeeded(on controller: WKUserContentController) {
        guard !controller.userScripts.contains(where: { $0.source == scriptSource }) else { return }
        controller.addUserScript(
            WKUserScript(
                source: scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .defaultClient
            )
        )
    }

    private static let scriptSource = """
        (() => {
            if (window.__denPictureInPictureStateInstalled) return;
            window.__denPictureInPictureStateInstalled = true;
            const handler = window.webkit?.messageHandlers?.denPictureInPictureState;
            if (!handler) return;
            const post = (active) => handler.postMessage({ active });
            const isWebKitPiP = (target) =>
                typeof target?.webkitPresentationMode === 'string' &&
                target.webkitPresentationMode === 'picture-in-picture';
            document.addEventListener('enterpictureinpicture', () => post(true), true);
            document.addEventListener('leavepictureinpicture', () => {
                post(Boolean(document.pictureInPictureElement));
            }, true);
            document.addEventListener('webkitpresentationmodechanged', (event) => {
                post(isWebKitPiP(event.target) || Boolean(document.pictureInPictureElement));
            }, true);
            if (window === window.top) {
                window.addEventListener('pagehide', () => post(false));
            }
        })();
        """
}

@MainActor
private final class PictureInPictureStateMessageRouter: NSObject, WKScriptMessageHandler {
    static let routers = NSMapTable<WKUserContentController, PictureInPictureStateMessageRouter>.weakToStrongObjects()
    let owners = NSMapTable<WKWebView, PictureInPictureStateBridge>.weakToWeakObjects()

    static func shared(for controller: WKUserContentController) -> PictureInPictureStateMessageRouter {
        if let existing = routers.object(forKey: controller) {
            return existing
        }
        let router = PictureInPictureStateMessageRouter()
        routers.setObject(router, forKey: controller)
        controller.add(router, contentWorld: .defaultClient, name: PictureInPictureStateBridge.handlerName)
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
