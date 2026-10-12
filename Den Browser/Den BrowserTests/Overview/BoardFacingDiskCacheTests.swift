import AppKit
import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct BoardFacingDiskCacheTests {
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

    @Test func pruneRemovesOrphansButKeepsExistingBoards() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = BoardFacingDiskCache(directoryURL: directory)
        let kept = BoardID()
        let removed = BoardID()
        let raster = try image()
        await disk.save(raster, for: kept, capturedAt: .now)
        await disk.save(raster, for: removed, capturedAt: .now)

        // Act
        await disk.prune(keeping: [kept])

        // Assert
        #expect(await disk.image(for: kept) != nil)
        #expect(await disk.image(for: removed) == nil)
    }

    @Test func clearingRejectsWritesCapturedBeforeClear() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = BoardFacingDiskCache(directoryURL: directory)
        let boardID = BoardID()
        let raster = try image()
        let capturedAt = Date.now
        await disk.save(raster, for: boardID, capturedAt: capturedAt)

        // Act
        await disk.removeAll()
        await disk.save(raster, for: boardID, capturedAt: capturedAt)

        // Assert
        #expect(await disk.image(for: boardID) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func diskBudgetEvictsOldestCapture() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = BoardID()
        let second = BoardID()
        let raster = try image()
        let initial = BoardFacingDiskCache(directoryURL: directory)
        await initial.save(raster, for: first, capturedAt: Date(timeIntervalSince1970: 1))
        let url = try #require(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let size = try #require(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        let limited = BoardFacingDiskCache(directoryURL: directory, maxCost: size)

        // Act
        await limited.save(raster, for: second, capturedAt: Date(timeIntervalSince1970: 2))

        // Assert
        #expect(await limited.image(for: first) == nil)
        #expect(await limited.image(for: second) != nil)
    }

    @Test func missingAndCorruptFilesAreCacheMisses() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = BoardID()
        try Data("broken".utf8).write(to: directory.appending(path: corrupt.rawValue.uuidString.lowercased() + ".png"))
        let disk = BoardFacingDiskCache(directoryURL: directory)

        // Act
        let missingImage = await disk.image(for: BoardID())
        let corruptImage = await disk.image(for: corrupt)

        // Assert
        #expect(missingImage == nil)
        #expect(corruptImage == nil)
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
