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

    @Test func facingClipsCornersUsingScaledCornerRadius() throws {
        // Arrange
        let scale: CGFloat = 2
        let context = try #require(
            CGContext(
                data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let raster = try #require(context.makeImage())
        let facing = NSImage(cgImage: raster, size: CGSize(width: 100, height: 100))
        let card = OverviewBoardFacing(
            board: BoardState(label: "Board", width: 600),
            isSelected: false,
            profileColor: .blue,
            boardHeight: 600,
            facingHeight: 120,
            facing: facing,
            scale: scale
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

        // At scale 2, cornerRadius should be 8 * 2 = 16px.
        // A point at (pointX: 2, pointY: rendered.height - 3) is outside the 16px corner arc,
        // so the facing image must be fully clipped out.
        let pointX = 2
        let pointY = rendered.height - 3
        let offset = pointY * pixels.bytesPerRow + pointX * 4
        let red = data[offset]
        let alpha = data[offset + 3]

        // Assert: Outside scaled corner radius, no content should leak
        #expect(alpha == 0, "Pixel at outer corner (2, 2) must be fully clipped; got red=\(red), alpha=\(alpha)")
    }
}
