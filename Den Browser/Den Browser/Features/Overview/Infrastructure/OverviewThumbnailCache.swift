import AppKit
import DenDomain
import Foundation
import Observation

@MainActor
@Observable
final class OverviewThumbnailCache {
    struct ThumbnailEntry {
        let capturedAt: ContinuousClock.Instant
        let estimatedCost: Int
    }

    private(set) var thumbnails: [BoardID: NSImage] = [:]
    @ObservationIgnored private var entries: [BoardID: ThumbnailEntry] = [:]
    @ObservationIgnored private var lruOrder: [BoardID] = []
    @ObservationIgnored private var totalCost: Int = 0
    @ObservationIgnored private var captures: [BoardID: UUID] = [:]

    // Budget counts the retained raster's actual row bytes, including Retina pixels.
    let maxCost: Int

    init(maxCost: Int = 64 * 1024 * 1024) {
        self.maxCost = maxCost
    }

    func image(for boardID: BoardID) -> NSImage? {
        if let image = thumbnails[boardID] {
            touch(boardID)
            return image
        }
        return nil
    }

    func lastCapturedInstant(for boardID: BoardID) -> ContinuousClock.Instant? {
        entries[boardID]?.capturedAt
    }

    func setThumbnail(_ image: NSImage, for boardID: BoardID, at instant: ContinuousClock.Instant = .now) {
        guard let raster = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let cost = raster.bytesPerRow * raster.height
        if let existing = entries[boardID] {
            totalCost -= existing.estimatedCost
        }

        let entry = ThumbnailEntry(capturedAt: instant, estimatedCost: cost)
        entries[boardID] = entry
        thumbnails[boardID] = NSImage(cgImage: raster, size: image.size)
        totalCost += cost
        touch(boardID)

        trimToCost()
    }

    func invalidate(for boardID: BoardID) {
        captures.removeValue(forKey: boardID)
        guard let existing = entries.removeValue(forKey: boardID) else { return }
        thumbnails.removeValue(forKey: boardID)
        totalCost -= existing.estimatedCost
        lruOrder.removeAll { $0 == boardID }
    }

    func removeAll() {
        captures.removeAll()
        entries.removeAll()
        thumbnails.removeAll()
        lruOrder.removeAll()
        totalCost = 0
    }

    private func touch(_ boardID: BoardID) {
        lruOrder.removeAll { $0 == boardID }
        lruOrder.append(boardID)
    }

    private func trimToCost() {
        while totalCost > maxCost, !lruOrder.isEmpty {
            let oldest = lruOrder.removeFirst()
            if let entry = entries.removeValue(forKey: oldest) {
                thumbnails.removeValue(forKey: oldest)
                totalCost -= entry.estimatedCost
            }
        }
    }

    func isCapturing(_ boardID: BoardID) -> Bool { captures[boardID] != nil }

    func beginCapture(for boardID: BoardID) -> UUID {
        let token = UUID()
        captures[boardID] = token
        return token
    }

    func finishCapture(_ token: UUID, for boardID: BoardID) {
        guard captures[boardID] == token else { return }
        captures.removeValue(forKey: boardID)
    }

    func setCapturedThumbnail(_ image: NSImage, for boardID: BoardID, token: UUID) {
        guard captures[boardID] == token else { return }
        setThumbnail(image, for: boardID)
    }
}
