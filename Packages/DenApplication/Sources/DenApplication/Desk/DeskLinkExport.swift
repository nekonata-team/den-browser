import DenDomain
import Foundation

public enum DeskLinkExport {
    public static func markdown(for desk: DeskState) -> String? {
        let links = desk.boards.compactMap { board -> String? in
            guard let url = board.currentSheetURL else { return nil }
            let label = escapeMarkdownLabel(board.displayName)
            return "- [\(label)](<\(url.absoluteString)>)"
        }
        guard !links.isEmpty else { return nil }

        return (["# \(escapeMarkdownLabel(desk.label))", ""] + links + [""]).joined(separator: "\n")
    }

    private static func escapeMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}
