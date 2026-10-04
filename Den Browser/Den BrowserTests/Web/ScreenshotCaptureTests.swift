import AppKit
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct ScreenshotCaptureTests {
    @Test func filenameUsesStableTimestamp() throws {
        let date = Date(timeIntervalSince1970: 0)
        #expect(
            ScreenshotOutput.suggestedFilename(
                scope: "Current Sheet Screenshot",
                date: date,
                timeZone: try #require(TimeZone(secondsFromGMT: 0)))
                == "Current Sheet Screenshot 1970-01-01 00.00.00.png")
    }

    @Test func outputEncodesPNGData() throws {
        let image = image(width: 120, height: 80)

        let data = try ScreenshotOutput.pngData(for: image)

        #expect(data.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]))
    }

    private func image(width: CGFloat, height: CGFloat) -> NSImage {
        let size = CGSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
