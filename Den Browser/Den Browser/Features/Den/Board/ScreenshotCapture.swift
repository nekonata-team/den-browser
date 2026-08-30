import AppKit
import UniformTypeIdentifiers
import WebKit

@MainActor
enum ScreenshotCapture {
    struct DeskItem {
        let label: String
        let image: NSImage
    }

    enum CaptureError: LocalizedError {
        case imageUnavailable
        case pngEncodingFailed
        case clipboardWriteFailed

        var errorDescription: String? {
            switch self {
            case .imageUnavailable:
                "The Current Sheet could not be captured."
            case .pngEncodingFailed:
                "The screenshot could not be encoded as PNG."
            case .clipboardWriteFailed:
                "The screenshot could not be copied to the clipboard."
            }
        }
    }

    static let deskHeaderHeight: CGFloat = 36
    static let deskSpacing: CGFloat = 12
    static let maximumDeskWidth: CGFloat = 16_384

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

    static func composeDesk(_ items: [DeskItem]) throws -> NSImage {
        guard !items.isEmpty else { throw CaptureError.imageUnavailable }

        let gapWidth = deskSpacing * CGFloat(items.count - 1)
        let naturalContentWidth = items.reduce(CGFloat.zero) { $0 + $1.image.size.width }
        guard naturalContentWidth > 0 else { throw CaptureError.imageUnavailable }
        let scale = min(1, maximumDeskWidth / (naturalContentWidth + gapWidth))
        let scaledSpacing = deskSpacing * scale
        let canvasSize = CGSize(
            width: (naturalContentWidth + gapWidth) * scale,
            height: (items.map(\.image.size.height).max() ?? 0) * scale + deskHeaderHeight)
        return NSImage(size: canvasSize, flipped: false) { _ in
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

            var horizontalOffset: CGFloat = 0
            for item in items {
                let sheetSize = CGSize(
                    width: item.image.size.width * scale,
                    height: item.image.size.height * scale)
                let sheetRect = NSRect(
                    x: horizontalOffset,
                    y: canvasSize.height - deskHeaderHeight - sheetSize.height,
                    width: sheetSize.width,
                    height: sheetSize.height)
                item.image.draw(in: sheetRect)

                let headerRect = NSRect(
                    x: horizontalOffset,
                    y: canvasSize.height - deskHeaderHeight,
                    width: sheetSize.width,
                    height: deskHeaderHeight)
                NSColor.controlBackgroundColor.setFill()
                NSBezierPath(rect: headerRect).fill()
                (item.label as NSString).draw(
                    in: headerRect.insetBy(dx: 10, dy: 9),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: NSColor.labelColor,
                    ])

                horizontalOffset += sheetSize.width + scaledSpacing
            }
            return true
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
            throw CaptureError.clipboardWriteFailed
        }
    }

    private static func pngData(for image: NSImage) throws -> Data {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw CaptureError.pngEncodingFailed
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
