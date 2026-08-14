import SwiftUI

struct KeyboardShortcutsView: View {
    var onClose: (() -> Void)?

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                if let onClose {
                    DenCloseButton(label: "Close Keyboard Shortcuts", action: onClose)
                }
            }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), alignment: .top)],
                    spacing: DenPanelLayout.contentSpacing
                ) {
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
                    item(["⌘", "L"], "Edit Focused Board Link"),
                    item(["⌘", "R"], "Reload Current Sheet"),
                    item(["⇧", "⌘", "R"], "Hard Reload Current Sheet"),
                    item(["⌘", "⌥", "⇧", "R"], "Reload Focused Desk Sheets"),
                    item(["⌘", "W"], "Remove Focused Board"),
                    item(["⇧", "⌘", "W"], "Close Profile Window"),
                    item(["⌘", "Q"], "Quit Den Browser"),
                    item(deskNumberShortcutTokens, "Focus Desk 1–10"),
                ] + ConfigurableShortcut.allCases.map(customItem)),
            ShortcutGuideSection(
                title: "Den Mode",
                items: [
                    item(["Escape"], "Exit Den Mode"),
                    item(["←", "/", "→", "or", "h", "/", "l"], "Focus previous / next Board"),
                    item(["↑", "/", "↓", "or", "j", "/", "k"], "Focus previous / next Desk"),
                    item(["Shift", "+", "movement"], "Move Focused Board"),
                    item(["/"], "Filter Boards in Focused Desk"),
                    item(["1–9", "/", "0"], "Focus Desk 1–10"),
                    item(["Shift", "+", "digit"], "Move Focused Board to Desk"),
                    item(["n", "/", "Space"], "Open Board"),
                    item(["⇧", "N"], "New Desk"),
                    item(["p"], "Save Desk as Preset"),
                    item(["⇧", "P"], "Replace Desk from Preset"),
                    item(["o"], "Overview"),
                    item(["Tab"], "Toggle Drawer"),
                    item([","], "Open Settings"),
                    item(["g", "then", "key"], "Start Essential"),
                    item(["?"], "Keyboard Shortcuts"),
                    item(["z"], "Toggle Zen View"),
                    item(["⇧", "F"], "Toggle Focus Mode"),
                ]),
            ShortcutGuideSection(
                title: "Board Actions",
                items: [
                    item(["[", "/", "]"], "Back / forward Sheet"),
                    item(["⇧", "[", "/", "⇧", "]"], "First / latest Sheet"),
                    item(["-", "/", "="], "Narrow / widen Board"),
                    item(["w", "then", "- / = / 1–9"], "Resize all Boards"),
                    item(["f"], "Toggle maximized Board"),
                    item(["c"], "Center Focused Board"),
                    item(["t"], "Pause / resume Sheet Navigation for Focused Board"),
                    item(["a"], "Keep Current Sheet in Drawer"),
                    item(["s"], "Capture Current Sheet Screenshot"),
                    item(["⇧", "S"], "Capture Focused Desk Screenshot"),
                    item(["Return"], "Duplicate Focused Board"),
                    item(["Shift", "+", "Return"], "New Board from First Sheet"),
                    item(["e"], "Edit Focused Board Link"),
                    item(["r"], "Rename Board"),
                    item(["x", "/", "d"], "Remove Focused Board"),
                    item(["u"], "Restore Removed Board"),
                    item(["⇧", "D"], "Delete Focused Desk"),
                    item(["⇧", "R"], "Rename Desk"),
                ]),
            ShortcutGuideSection(
                title: "Overview",
                items: [
                    item(["←", "/", "→", "or", "h", "/", "l"], "Select Board"),
                    item(["↑", "/", "↓", "or", "j", "/", "k"], "Select Desk"),
                    item(["/"], "Search / Filter"),
                    item(["Shift", "+", "movement"], "Move selected Board"),
                    item(["Return"], "Enter selection"),
                    item(["Escape"], "Return to Den Mode"),
                ]),
            ShortcutGuideSection(
                title: "Drawer",
                items: [
                    item(["Tab"], "Close Drawer in Den Mode"),
                    item(["/"], "Search Drawer Items in Den Mode"),
                    item(["↑", "/", "↓", "or", "k", "/", "j"], "Select Drawer Item"),
                    item(["Return"], "Toggle Drawer Preview"),
                    item(["p"], "Place as Board"),
                    item(["x", "/", "d", "or", "Delete"], "Discard Drawer Item"),
                    item(["Escape"], "Exit Den Mode / close Drawer"),
                ]),
            ShortcutGuideSection(
                title: "Sheet Input",
                items: [
                    item(["a", "then", "link hint"], "Keep link in Drawer with Sheet Navigation")
                ]),
        ]
    }

    private func customItem(_ action: ConfigurableShortcut) -> ShortcutGuideItem {
        guard let binding = preferences.shortcut(for: action) else {
            return item(["Unassigned"], action.label)
        }
        return ShortcutGuideItem(
            keys: binding.displayTokens,
            label: action.label,
            accessibilityKeys: binding.accessibilityLabel)
    }

    private var deskNumberShortcutTokens: [String] {
        guard let binding = preferences.deskNumberBinding else { return ["Unassigned"] }
        return Array(binding.displayTokens.dropLast()) + ["1–9, 0"]
    }

    private func item(_ keys: [String], _ label: String) -> ShortcutGuideItem {
        ShortcutGuideItem(keys: keys, label: label, accessibilityKeys: keys.joined(separator: " "))
    }

    private func shortcutSection(_ section: ShortcutGuideSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(section.items) { item in
                HStack(spacing: DenPanelLayout.controlSpacing) {
                    ShortcutChip(tokens: item.keys, width: 112)
                    Text(item.label)
                        .font(.caption)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.label), \(item.accessibilityKeys)")
            }
        }
        .padding(DenPanelLayout.contentSpacing)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous))
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
        .font(.caption2.monospaced().weight(.medium))
        .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
        .frame(width: width)
        .frame(minHeight: 18)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            isRecording ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
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
