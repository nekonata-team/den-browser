import AppKit
import DenDomain
import DenInfrastructure
import Foundation
import Observation

@MainActor
@Observable
final class BoardFacingCache {
    struct FacingEntry {
        let capturedAt: ContinuousClock.Instant?
        let estimatedCost: Int
    }

    private(set) var facings: [BoardID: NSImage] = [:]
    @ObservationIgnored private var entries: [BoardID: FacingEntry] = [:]
    @ObservationIgnored private var lruOrder: [BoardID] = []
    @ObservationIgnored private var totalCost: Int = 0
    @ObservationIgnored private var captures: [BoardID: UUID] = [:]

    @ObservationIgnored private let disk: BoardFacingDiskCache?
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private var loads: [BoardID: UUID] = [:]

    // Budget counts the retained raster's actual row bytes, including Retina pixels.
    let maxCost: Int

    init(maxCost: Int = 64 * 1024 * 1024, disk: BoardFacingDiskCache? = nil) {
        self.maxCost = maxCost
        self.disk = disk
    }

    func image(for boardID: BoardID) -> NSImage? {
        if let image = facings[boardID] {
            touch(boardID)
            return image
        }
        return nil
    }

    func lastCapturedInstant(for boardID: BoardID) -> ContinuousClock.Instant? {
        entries[boardID]?.capturedAt
    }

    func setFacing(
        _ image: NSImage, for boardID: BoardID, at instant: ContinuousClock.Instant? = .now, persist: Bool = true
    ) {
        guard let raster = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let cost = raster.bytesPerRow * raster.height
        if let existing = entries[boardID] {
            totalCost -= existing.estimatedCost
        }

        let entry = FacingEntry(capturedAt: instant, estimatedCost: cost)
        entries[boardID] = entry
        facings[boardID] = NSImage(cgImage: raster, size: image.size)
        totalCost += cost
        touch(boardID)

        trimToCost()
        if persist, let disk {
            let previous = pendingWrite
            let capturedAt = Date.now
            pendingWrite = Task {
                await previous?.value
                await disk.save(raster, for: boardID, capturedAt: capturedAt)
            }
        }
    }

    func loadFacing(for boardID: BoardID) async {
        guard facings[boardID] == nil, loads[boardID] == nil, let disk else { return }
        let token = UUID()
        loads[boardID] = token
        defer { if loads[boardID] == token { loads.removeValue(forKey: boardID) } }
        await pendingWrite?.value
        let raster = await disk.image(for: boardID)
        guard !Task.isCancelled, loads[boardID] == token, facings[boardID] == nil, let raster else { return }
        setFacing(
            NSImage(cgImage: raster, size: CGSize(width: raster.width, height: raster.height)), for: boardID, at: nil,
            persist: false)
    }

    func flushPendingWrites() async { await pendingWrite?.value }

    func clearDisk() async {
        removeAll()
        await disk?.removeAll()
    }

    func invalidate(for boardID: BoardID) {
        captures.removeValue(forKey: boardID)
        loads.removeValue(forKey: boardID)
        guard let existing = entries.removeValue(forKey: boardID) else { return }
        facings.removeValue(forKey: boardID)
        totalCost -= existing.estimatedCost
        lruOrder.removeAll { $0 == boardID }
    }

    func removeAll() {
        captures.removeAll()
        loads.removeAll()
        entries.removeAll()
        facings.removeAll()
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
                facings.removeValue(forKey: oldest)
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

    func setCapturedFacing(_ image: NSImage, for boardID: BoardID, token: UUID) {
        guard captures[boardID] == token else { return }
        setFacing(image, for: boardID)
    }
}
