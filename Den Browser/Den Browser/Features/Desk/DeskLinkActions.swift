import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import UniformTypeIdentifiers

@MainActor
enum DeskLinkOutput {
    static func saveMarkdown(
        _ markdown: String,
        suggestedFilename: String,
        attachedTo window: NSWindow?
    ) async throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename

        let response = await withCheckedContinuation { continuation in
            let completion: (NSApplication.ModalResponse) -> Void = {
                continuation.resume(returning: $0)
            }
            if let window {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }

        guard response == .OK, let destination = panel.url else { return nil }
        try Data(markdown.utf8).write(to: destination, options: .atomic)
        return destination
    }
}

@MainActor
final class DeskLinkActions {
    private let context: WindowNativeContext
    private var state: DenState { context.storage.state }
    private var focusedDesk: DeskState? { context.focusedDesk }

    init(context: WindowNativeContext) {
        self.context = context
    }

    func exportFocusedDeskLinks() {
        guard let focusedDesk else {
            context.feedback.publish("No Focused Desk.", severity: .warning)
            return
        }
        exportDeskLinks(for: focusedDesk.id)
    }

    func copyFocusedDeskLinks() {
        guard let focusedDesk else {
            context.feedback.publish("No Focused Desk.", severity: .warning)
            return
        }
        copyDeskLinks(for: focusedDesk.id)
    }

    func exportDeskLinks(for deskID: DeskID) {
        guard
            let desk = state.desks.first(where: { $0.id == deskID }),
            let markdown = DeskLinkExport.markdown(for: desk)
        else {
            context.feedback.publish("Desk has no Current Sheet links.", severity: .warning)
            return
        }

        let filename = "\(desk.label) Links.md"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let destination = try await DeskLinkOutput.saveMarkdown(
                    markdown,
                    suggestedFilename: filename,
                    attachedTo: NSApp.keyWindow)
                {
                    context.feedback.publish("Saved \(destination.lastPathComponent).", severity: .success)
                }
            } catch {
                context.feedback.publish("Desk links export failed: \(error.localizedDescription)", severity: .error)
            }
        }
    }

    func copyDeskLinks(for deskID: DeskID) {
        guard
            let desk = state.desks.first(where: { $0.id == deskID }),
            let markdown = DeskLinkExport.markdown(for: desk)
        else {
            context.feedback.publish("Desk has no Current Sheet links.", severity: .warning)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        context.feedback.publish("Copied Desk Links as Markdown.", severity: .success)
    }
}
