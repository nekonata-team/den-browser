import Foundation
import WebKit

@MainActor
enum JSONViewerRuntime {
    static let contentWorld = WKContentWorld.world(name: "dev.nekonata.denbrowser.json-viewer")

    static func install(on userContentController: WKUserContentController) {
        guard !source.isEmpty,
            !userContentController.userScripts.contains(where: { $0.source == source })
        else { return }
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true,
                in: contentWorld
            )
        )
    }

    private static let source: String = {
        let bundles = [
            Bundle.main,
            Bundle(for: JSONViewerBundleToken.self),
            Bundle(identifier: "dev.nekonata.denbrowser"),
        ].compactMap { $0 }
        for bundle in bundles {
            guard
                let url = bundle.url(forResource: "JSONViewer", withExtension: "js"),
                let source = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            return source
        }
        return ""
    }()
}

private final class JSONViewerBundleToken: NSObject {}
