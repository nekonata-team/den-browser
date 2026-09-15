import Foundation
import WebKit

@MainActor
enum SheetDOMRuntime {
    static let contentWorld = WKContentWorld.world(name: "dev.nekonata.denbrowser.sheet-dom")

    static func install(on userContentController: WKUserContentController) {
        guard !source.isEmpty else { return }
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: contentWorld
            ))
    }

    private static let source: String = {
        let bundles = [
            Bundle.main,
            Bundle(for: SheetDOMBundleToken.self),
            Bundle(identifier: "dev.nekonata.denbrowser"),
        ].compactMap { $0 }
        for bundle in bundles {
            guard
                let url = bundle.url(forResource: "SheetDOM", withExtension: "js"),
                let source = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            return source
        }
        return ""
    }()
}

private final class SheetDOMBundleToken: NSObject {}
