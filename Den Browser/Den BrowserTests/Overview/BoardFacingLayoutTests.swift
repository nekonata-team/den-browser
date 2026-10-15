import AppKit
import DenDomain
import SwiftUI
import Testing

@testable import Den_Browser

@MainActor
struct BoardFacingLayoutTests {
    @Test func facingKeepsBothHorizontalEdgesWhenItsAspectRatioDiffersFromBoard() throws {
        // Arrange
        let context = try #require(
            CGContext(
                data: nil, width: 80, height: 120, bitsPerComponent: 8, bytesPerRow: 320,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 120))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 72, y: 0, width: 8, height: 120))
        let raster = try #require(context.makeImage())
        let facing = NSImage(cgImage: raster, size: CGSize(width: 80, height: 120))
        let card = OverviewBoardFacing(
            board: BoardState(label: "Board", width: 400),
            isSelected: false,
            profileColor: .blue,
            boardHeight: 800,
            facing: facing
        )
        .environment(\.colorScheme, .light)

        // Act
        let rendered = try #require(ImageRenderer(content: card).cgImage)
        let pixels = try #require(
            CGContext(
                data: nil, width: rendered.width, height: rendered.height, bitsPerComponent: 8,
                bytesPerRow: rendered.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        pixels.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        let data = try #require(pixels.data).assumingMemoryBound(to: UInt8.self)
        let row = rendered.height / 2 * pixels.bytesPerRow
        let left = row + 4 * 4
        let right = row + (rendered.width - 5) * 4

        // Assert
        #expect(Int(data[left]) > 2 * Int(data[left + 2]), "The left red edge must remain visible")
        #expect(Int(data[right + 2]) > 2 * Int(data[right]), "The right blue edge must remain visible")
    }
}
