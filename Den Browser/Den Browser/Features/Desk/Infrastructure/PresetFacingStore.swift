import AppKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

actor PresetFacingDiskStore {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func fileURL(for presetID: UUID, at index: Int) -> URL {
        directoryURL
            .appending(path: presetID.uuidString.lowercased(), directoryHint: .isDirectory)
            .appending(path: "\(index).png")
    }

    func image(for presetID: UUID, at index: Int) -> CGImage? {
        let url = fileURL(for: presetID, at: index)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func save(_ image: CGImage, for presetID: UUID, at index: Int) {
        let url = fileURL(for: presetID, at: index)
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
            else { return }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return }
            try (data as Data).write(to: url, options: .atomic)
        } catch {
            // Cache failures do not affect preset operations.
        }
    }

    func remove(for presetID: UUID) {
        let dir = directoryURL.appending(path: presetID.uuidString.lowercased(), directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dir)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

@MainActor
@Observable
final class PresetFacingStore {
    private(set) var facings: [UUID: [Int: NSImage]] = [:]
    @ObservationIgnored private let disk: PresetFacingDiskStore?
    @ObservationIgnored private var loadingTasks: [UUID: Task<Void, Never>] = [:]

    init(disk: PresetFacingDiskStore? = nil) {
        self.disk = disk
    }

    func image(for presetID: UUID, at index: Int) -> NSImage? {
        facings[presetID]?[index]
    }

    func setFacing(_ image: NSImage, for presetID: UUID, at index: Int) {
        if facings[presetID] == nil {
            facings[presetID] = [:]
        }
        facings[presetID]?[index] = image

        if let disk, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            Task {
                await disk.save(cgImage, for: presetID, at: index)
            }
        }
    }

    func loadFacings(for presetID: UUID, boardCount: Int) async {
        guard facings[presetID] == nil, loadingTasks[presetID] == nil, let disk else { return }
        let task = Task {
            var loaded: [Int: NSImage] = [:]
            for index in 0..<boardCount {
                if let cgImage = await disk.image(for: presetID, at: index) {
                    loaded[index] = NSImage(
                        cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
                }
            }
            if !Task.isCancelled {
                facings[presetID] = loaded
            }
        }
        loadingTasks[presetID] = task
        await task.value
        loadingTasks.removeValue(forKey: presetID)
    }

    func remove(for presetID: UUID) {
        facings.removeValue(forKey: presetID)
        loadingTasks[presetID]?.cancel()
        loadingTasks.removeValue(forKey: presetID)
        if let disk {
            Task { await disk.remove(for: presetID) }
        }
    }

    func removeAll() {
        facings.removeAll()
        for task in loadingTasks.values { task.cancel() }
        loadingTasks.removeAll()
        if let disk {
            Task { await disk.removeAll() }
        }
    }
}
