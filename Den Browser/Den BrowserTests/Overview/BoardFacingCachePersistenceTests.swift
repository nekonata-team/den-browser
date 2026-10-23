import AppKit
import DenDomain
import DenInfrastructure
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct BoardFacingCachePersistenceTests {
    @Test func persistedSnapshotLoadsIntoFreshMemoryCacheWithoutStartingRecaptureSuppression() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let boardID = BoardID()
        let first = BoardFacingCache(disk: BoardFacingDiskCache(directoryURL: directory))
        let raster = try image()
        first.setFacing(
            NSImage(cgImage: raster, size: CGSize(width: raster.width, height: raster.height)), for: boardID)
        await first.flushPendingWrites()
        let restored = BoardFacingCache(disk: BoardFacingDiskCache(directoryURL: directory))

        // Act
        await restored.loadFacing(for: boardID)

        // Assert
        let facing = try #require(restored.image(for: boardID))
        let restoredRaster = try #require(facing.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(restoredRaster.width == raster.width)
        #expect(restoredRaster.height == raster.height)
        #expect(restored.lastCapturedInstant(for: boardID) == nil)
    }

    private func image() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        return try #require(context.makeImage())
    }
}
