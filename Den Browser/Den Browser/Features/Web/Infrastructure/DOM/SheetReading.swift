import DenIPCProtocol
import Foundation
import WebKit

@MainActor
enum SheetReading {
    private static let source: String? = {
        let bundles = [Bundle.main, Bundle(for: SheetReadingBundleToken.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "SheetRead", withExtension: "js"),
                let source = try? String(contentsOf: url, encoding: .utf8)
            {
                return source
            }
        }
        return nil
    }()

    static func read(in webView: WKWebView, within: String? = nil) async throws -> DenIPCResultPayload {
        guard let source else {
            throw NSError(
                domain: "SheetReading", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled Markdown converter is unavailable"])
        }
        guard let withinLiteral = String(data: try JSONEncoder().encode(within), encoding: .utf8) else {
            throw SheetInteractionError.executionFailed("Failed to encode reading scope")
        }
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(
                source + """

                    (() => {
                        try { return denSheetRead.read(\(withinLiteral)); }
                        catch (error) { return { error: String(error) }; }
                    })();
                    """, in: nil, in: SheetDOMRuntime.contentWorld
            ) { result in
                do {
                    let value = try result.get()
                    if let message = (value as? [String: String])?["error"] {
                        throw SheetInteractionError.executionFailed(message)
                    }
                    guard let result = value as? [String: String],
                        let title = result["title"], let url = result["url"], let markdown = result["markdown"]
                    else {
                        throw NSError(
                            domain: "SheetReading", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Markdown converter returned an invalid result"])
                    }
                    continuation.resume(returning: .reading(title: title, url: url, markdown: markdown))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class SheetReadingBundleToken: NSObject {}
