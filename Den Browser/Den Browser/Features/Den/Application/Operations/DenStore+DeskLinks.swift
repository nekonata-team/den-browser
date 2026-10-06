import AppKit
import DenDomain
import UniformTypeIdentifiers

@MainActor
enum DeskLinkExport {
    static func markdown(for desk: DeskState) -> String? {
        let links = desk.boards.compactMap { board -> String? in
            guard let url = board.currentSheetURL else { return nil }
            let label = escapeMarkdownLabel(board.displayName)
            return "- [\(label)](<\(url.absoluteString)>)"
        }
        guard !links.isEmpty else { return nil }

        return (["# \(escapeMarkdownLabel(desk.label))", ""] + links + [""]).joined(separator: "\n")
    }

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

    private static func escapeMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

extension DenStore {
    var canExportFocusedDeskLinks: Bool {
        guard let focusedDesk else { return false }
        return canExportDeskLinks(for: focusedDesk.id)
    }

    func canExportDeskLinks(for deskID: UUID) -> Bool {
        state.desks.first(where: { $0.id == deskID })?.boards.contains {
            $0.currentSheetURL != nil
        } == true
    }

    func exportFocusedDeskLinks() {
        guard let focusedDesk else {
            reportFeedback("No Focused Desk.", severity: .warning)
            return
        }
        exportDeskLinks(for: focusedDesk.id)
    }

    func copyFocusedDeskLinks() {
        guard let focusedDesk else {
            reportFeedback("No Focused Desk.", severity: .warning)
            return
        }
        copyDeskLinks(for: focusedDesk.id)
    }

    func exportDeskLinks(for deskID: UUID) {
        guard
            let desk = state.desks.first(where: { $0.id == deskID }),
            let markdown = DeskLinkExport.markdown(for: desk)
        else {
            reportFeedback("Desk has no Current Sheet links.", severity: .warning)
            return
        }

        let filename = "\(desk.label) Links.md"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let destination = try await DeskLinkExport.saveMarkdown(
                    markdown,
                    suggestedFilename: filename,
                    attachedTo: NSApp.keyWindow)
                {
                    reportFeedback("Saved \(destination.lastPathComponent).", severity: .success)
                }
            } catch {
                reportFeedback("Desk links export failed: \(error.localizedDescription)", severity: .error)
            }
        }
    }

    func copyDeskLinks(for deskID: UUID) {
        guard
            let desk = state.desks.first(where: { $0.id == deskID }),
            let markdown = DeskLinkExport.markdown(for: desk)
        else {
            reportFeedback("Desk has no Current Sheet links.", severity: .warning)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        reportFeedback("Copied Desk Links as Markdown.", severity: .success)
    }
}
