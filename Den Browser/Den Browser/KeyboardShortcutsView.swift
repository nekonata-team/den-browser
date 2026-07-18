import SwiftUI

struct KeyboardShortcutsView: View {
    var onClose: (() -> Void)?

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Close Keyboard Shortcuts")
                }
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .top)], spacing: 12) {
                    ForEach(sections) { section in
                        shortcutSection(section)
                    }
                }
                .padding(1)
            }
        }
    }

    private var sections: [ShortcutGuideSection] {
        [
            ShortcutGuideSection(
                title: "App and Sheet Input",
                items: [
                    item(["⌃", "⌘", "P"], "Open Profile panel"),
                    item(["⌘", "T"], "Open Board"),
                    item(["⌘", "R"], "Reload Current Sheet"),
                    item(["⌘", "W"], "Remove Focused Board"),
                    item(["⇧", "⌘", "W"], "Close Profile Window"),
                    item(["⌘", "Q"], "Quit Den Browser"),
                ] + ShortcutAction.allCases.map(customItem)),
            ShortcutGuideSection(
                title: "Den Mode",
                items: [
                    item(["Escape"], "Exit Den Mode"),
                    item(["←", "/", "→", "or", "h", "/", "l"], "Focus previous / next Board"),
                    item(["↑", "/", "↓", "or", "j", "/", "k"], "Focus previous / next Desk"),
                    item(["Shift", "+", "movement"], "Move Focused Board"),
                    item(["1–9", "/", "0"], "Focus Desk 1–10"),
                    item(["Shift", "+", "digit"], "Move Focused Board to Desk"),
                    item(["n", "/", "Space"], "Open Board"),
                    item(["⇧", "N"], "New Desk"),
                    item(["p"], "Save Desk as Preset"),
                    item(["⇧", "P"], "Manage Desk Presets"),
                    item(["o"], "Overview"),
                    item(["?"], "Keyboard Shortcuts"),
                    item(["z"], "Toggle Zen View"),
                ]),
            ShortcutGuideSection(
                title: "Board Actions",
                items: [
                    item(["[", "/", "]"], "Back / forward Sheet"),
                    item(["-", "/", "="], "Narrow / widen Board"),
                    item(["w", "then", "1–9"], "Resize all Boards to fit"),
                    item(["f"], "Toggle maximized Board"),
                    item(["c"], "Center Focused Board"),
                    item(["Return"], "Duplicate Current Sheet"),
                    item(["x", "/", "d"], "Remove Focused Board"),
                    item(["u"], "Restore Removed Board"),
                    item(["⇧", "D"], "Delete Focused Desk"),
                ]),
            ShortcutGuideSection(
                title: "Overview",
                items: [
                    item(["←", "/", "→", "or", "h", "/", "l"], "Select Board"),
                    item(["↑", "/", "↓", "or", "j", "/", "k"], "Select Desk"),
                    item(["Shift", "+", "movement"], "Move selected Board"),
                    item(["Return"], "Enter selection"),
                    item(["Escape"], "Return to Den Mode"),
                ]),
        ]
    }

    private func customItem(_ action: ShortcutAction) -> ShortcutGuideItem {
        guard let binding = preferences.shortcut(for: action) else {
            return item(["Unassigned"], action.label)
        }
        return ShortcutGuideItem(
            keys: binding.displayTokens,
            label: action.label,
            accessibilityKeys: binding.accessibilityLabel)
    }

    private func item(_ keys: [String], _ label: String) -> ShortcutGuideItem {
        ShortcutGuideItem(keys: keys, label: label, accessibilityKeys: keys.joined(separator: " "))
    }

    private func shortcutSection(_ section: ShortcutGuideSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(section.items) { item in
                HStack(spacing: 10) {
                    ShortcutChip(tokens: item.keys, width: 112)
                    Text(item.label)
                        .font(.system(size: 12))
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.label), \(item.accessibilityKeys)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ShortcutChip: View {
    let tokens: [String]
    let width: CGFloat
    var isRecording = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Text(token)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
        .frame(width: width)
        .frame(minHeight: 18)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            isRecording ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isRecording ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.12),
                    lineWidth: 1
                )
        }
    }
}

private struct ShortcutGuideSection: Identifiable {
    let title: String
    let items: [ShortcutGuideItem]
    var id: String { title }
}

private struct ShortcutGuideItem: Identifiable {
    let keys: [String]
    let label: String
    let accessibilityKeys: String
    var id: String { titleKey }
    private var titleKey: String { "\(label)-\(keys.joined())" }
}
