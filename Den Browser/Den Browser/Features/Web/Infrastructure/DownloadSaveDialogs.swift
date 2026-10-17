import AppKit
import Foundation

struct PendingDownloadSaveDialog {
    let panel: NSSavePanel
    let suggestedFilename: String
    let downloadKey: ObjectIdentifier
    let completion: @MainActor (URL?, Bool) -> Void
}

enum DownloadSaveDialogError: LocalizedError {
    case unavailable
    case invalidDestination
    case destinationExists

    var errorDescription: String? {
        switch self {
        case .unavailable: "Save dialog not found or already resolved."
        case .invalidDestination: "Destination must be an absolute file path in an existing writable directory."
        case .destinationExists: "Destination already exists. Use --overwrite to replace it."
        }
    }
}

@MainActor
final class DownloadSaveDialogs {
    private(set) var pending: [UUID: PendingDownloadSaveDialog] = [:]

    func present(
        suggestedFilename: String,
        downloadKey: ObjectIdentifier,
        in window: NSWindow?,
        completion: @escaping @MainActor (URL?, Bool) -> Void
    ) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        let id = register(
            panel: panel, suggestedFilename: suggestedFilename, downloadKey: downloadKey, completion: completion)
        let complete: @MainActor @Sendable (NSApplication.ModalResponse) -> Void = {
            [weak self, weak panel] response in
            self?.resolve(id: id, destination: response == .OK ? panel?.url : nil, overwrite: true)
        }
        if let window = window ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            panel.begin(completionHandler: complete)
        }
    }

    @discardableResult
    func register(
        panel: NSSavePanel,
        suggestedFilename: String,
        downloadKey: ObjectIdentifier,
        completion: @escaping @MainActor (URL?, Bool) -> Void
    ) -> UUID {
        let id = UUID()
        pending[id] = PendingDownloadSaveDialog(
            panel: panel, suggestedFilename: suggestedFilename, downloadKey: downloadKey, completion: completion)
        return id
    }

    func save(id: UUID, path: String, overwrite: Bool) throws {
        guard pending[id] != nil else { throw DownloadSaveDialogError.unavailable }
        guard path.hasPrefix("/"), !path.utf8.contains(0) else {
            throw DownloadSaveDialogError.invalidDestination
        }
        let destination = URL(fileURLWithPath: path).standardizedFileURL
        let directory = destination.deletingLastPathComponent()
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue, fileManager.isWritableFile(atPath: directory.path)
        else { throw DownloadSaveDialogError.invalidDestination }
        // Inspect the entry itself so a dangling symlink also requires overwrite permission.
        if let attributes = try? fileManager.attributesOfItem(atPath: destination.path) {
            guard
                attributes[.type] as? FileAttributeType == .typeRegular
                    || attributes[.type] as? FileAttributeType == .typeSymbolicLink
            else { throw DownloadSaveDialogError.invalidDestination }
            guard overwrite else { throw DownloadSaveDialogError.destinationExists }
        }
        resolve(id: id, destination: destination, overwrite: overwrite)
    }

    func cancel(id: UUID) throws {
        guard pending[id] != nil else { throw DownloadSaveDialogError.unavailable }
        resolve(id: id, destination: nil, overwrite: false)
    }

    func resolve(id: UUID, destination: URL?, overwrite: Bool) {
        guard let pending = pending.removeValue(forKey: id) else { return }
        // Remove first: dismissing the panel also invokes its native completion handler.
        if pending.panel.isVisible || pending.panel.sheetParent != nil {
            pending.panel.cancel(nil)
        }
        pending.completion(destination, overwrite)
    }

    func cancelAll(for downloadKey: ObjectIdentifier? = nil) {
        let ids = pending.compactMap { id, pending in
            downloadKey == nil || pending.downloadKey == downloadKey ? id : nil
        }
        for id in ids {
            resolve(id: id, destination: nil, overwrite: false)
        }
    }
}
