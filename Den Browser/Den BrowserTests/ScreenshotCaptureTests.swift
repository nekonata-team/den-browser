import AppKit
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct ScreenshotCaptureTests {
    @Test func deskCompositionPreservesWidthsAndCapsWideImages() throws {
        let regular = try ScreenshotCapture.composeDesk([
            .init(label: "Alpha", image: image(width: 120, height: 80)),
            .init(label: "Bravo", image: image(width: 240, height: 80)),
        ])

        #expect(
            regular.size
                == CGSize(
                    width: 120 + ScreenshotCapture.deskSpacing + 240,
                    height: 80 + ScreenshotCapture.deskHeaderHeight))
        #expect(regular.tiffRepresentation != nil)

        let wide = try ScreenshotCapture.composeDesk([
            .init(label: "Alpha", image: image(width: 10_000, height: 100)),
            .init(label: "Bravo", image: image(width: 10_000, height: 100)),
        ])
        #expect(wide.size.width == ScreenshotCapture.maximumDeskWidth)
        #expect(wide.size.height < 100 + ScreenshotCapture.deskHeaderHeight)
    }

    @Test func filenameUsesStableTimestamp() throws {
        let date = Date(timeIntervalSince1970: 0)
        #expect(
            ScreenshotOutput.suggestedFilename(
                scope: "Desk Screenshot",
                date: date,
                timeZone: try #require(TimeZone(secondsFromGMT: 0)))
                == "Desk Screenshot 1970-01-01 00.00.00.png")
    }

    @Test func outputEncodesPNGData() throws {
        let image = try ScreenshotCapture.composeDesk([
            .init(label: "Alpha", image: image(width: 120, height: 80))
        ])

        let data = try ScreenshotOutput.pngData(for: image)

        #expect(data.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]))
    }

    private func image(width: CGFloat, height: CGFloat) -> NSImage {
        NSImage(size: CGSize(width: width, height: height))
    }
}
