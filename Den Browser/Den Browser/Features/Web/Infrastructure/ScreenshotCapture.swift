import AppKit
import UniformTypeIdentifiers
import WebKit

@MainActor
enum ScreenshotCapture {
    enum CaptureError: LocalizedError {
        case imageUnavailable

        var errorDescription: String? {
            switch self {
            case .imageUnavailable:
                "The Current Sheet could not be captured."
            }
        }
    }

    static func visibleCurrentSheet(in webView: WKWebView) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = true
            webView.takeSnapshot(with: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: CaptureError.imageUnavailable)
                }
            }
        }
    }

}

@MainActor
enum ScreenshotOutput {
    enum OutputError: LocalizedError {
        case pngEncodingFailed
        case clipboardWriteFailed

        var errorDescription: String? {
            switch self {
            case .pngEncodingFailed:
                "The screenshot could not be encoded as PNG."
            case .clipboardWriteFailed:
                "The screenshot could not be copied to the clipboard."
            }
        }
    }

    static func savePNG(
        _ image: NSImage,
        suggestedFilename: String,
        attachedTo window: NSWindow?
    ) async throws -> URL? {
        let data = try pngData(for: image)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename

        let response = await withCheckedContinuation { continuation in
            let completion: (NSApplication.ModalResponse) -> Void = {
                continuation.resume(returning: $0)
            }
            if let window {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }

        guard response == .OK, let destination = panel.url else { return nil }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func copyPNG(_ image: NSImage) throws {
        let data = try pngData(for: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else {
            throw OutputError.clipboardWriteFailed
        }
    }

    static func pngData(for image: NSImage) throws -> Data {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw OutputError.pngEncodingFailed
        }
        return data
    }

    static func suggestedFilename(
        scope: String,
        date: Date = .now,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(scope) \(formatter.string(from: date)).png"
    }
}
