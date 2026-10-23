import CoreGraphics
import DenDomain
import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor BoardFacingDiskCache {
    private let directoryURL: URL
    private let maxCost: Int
    private var minimumCaptureDate = Date.distantPast

    public init(directoryURL: URL, maxCost: Int = 128 * 1024 * 1024) {
        self.directoryURL = directoryURL
        self.maxCost = maxCost
    }

    public func image(for boardID: BoardID) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL(for: boardID) as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0, width <= 720, height <= 720
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    public func save(_ image: CGImage, for boardID: BoardID, capturedAt: Date) {
        guard capturedAt >= minimumCaptureDate else { return }
        let url = fileURL(for: boardID)
        if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            date > capturedAt
        {
            return
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try (data as Data).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: capturedAt], ofItemAtPath: url.path)
            trimToCost()
        } catch {
            // Cache failures do not affect Board operations.
        }
    }

    public func prune(keeping boardIDs: Set<BoardID>) {
        let filenames = Set(boardIDs.map { fileURL(for: $0).lastPathComponent })
        for url in files() where !filenames.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
        trimToCost()
    }

    public func removeAll() {
        minimumCaptureDate = .now
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func fileURL(for boardID: BoardID) -> URL {
        directoryURL.appending(path: boardID.rawValue.uuidString.lowercased() + ".png")
    }

    private func files() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "png" }
    }

    private func trimToCost() {
        let entries = files().compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let size = values.fileSize
            else { return nil }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var cost = entries.reduce(0) { $0 + $1.1 }
        for (url, size, _) in entries where cost > maxCost {
            do {
                try FileManager.default.removeItem(at: url)
                cost -= size
            } catch { continue }
        }
    }
}
