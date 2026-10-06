import DenDomain
import SFSafeSymbols
import SwiftUI

struct KeyboardShortcutsView: View {
    var onClose: (() -> Void)?

    @Environment(AppPreferences.self) private var preferences
    @FocusState private var isSearchFocused: Bool
    @State private var query = ""

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

            searchField

            ScrollView {
                if visibleSections.isEmpty {
                    Text("No shortcuts found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    LazyVStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
                        ForEach(visibleSections) { section in
                            shortcutSection(section)
                        }
                    }
                    .padding(1)
                }
            }
        }
        .onAppear { isSearchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .magnifyingglass)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(text: $query, prompt: Text("Search shortcuts")) {
                Text("Search shortcuts")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var visibleSections: [ShortcutGuideSection] {
        sections.compactMap { $0.filtered(matching: query) }
    }

    private var sections: [ShortcutGuideSection] {
        [
            ShortcutGuideSection(
                title: "Den Mode and Navigation",
                items: [
                    customItem(.toggleDenMode),
                    item(["Escape"], "Exit Den Mode"),
                    customItem(.focusPreviousDesk),
                    customItem(.focusNextDesk),
                    customItem(.returnToPreviousDesk),
                    item(["↑", "/", "↓", "or", "j", "/", "k"], "Focus previous / next Desk"),
                    item(deskNumberShortcutTokens, "Focus Desk 1–10"),
                    item(["1–9", "/", "0"], "Focus Desk 1–10"),
                    customItem(.focusPreviousBoard),
                    customItem(.focusNextBoard),
                    item(["←", "/", "→", "or", "h", "/", "l"], "Focus previous / next Board"),
                    item(["<", "/", ">"], "Browse Boards without changing focus"),
                    item(["/"], "Filter Boards in Focused Desk"),
                    item(["Shift", "+", "movement"], "Move Focused Board"),
                    item(["Shift", "+", "digit"], "Move Focused Board to Desk"),
                    customItem(.moveFocusedBoardLeft),
                    customItem(.moveFocusedBoardRight),
                    item(["m"], "Set / clear Anchor Board"),
                    item(["⇧", "M"], "Jump to Anchor Board / return to origin"),
                ]),
            ShortcutGuideSection(
                title: "Board",
                items: [
                    item(["⌘", "T"], "Open Board"),
                    item(["n", "/", "Space"], "Den Mode: Open Board"),
                    item(["v"], "Den Mode: Open Board from clipboard"),
                    item(["g", "then", "key"], "Den Mode: Start Essential"),
                    item(["y"], "Den Mode: Copy Focused Board URL / working directory / session"),
                    item(["⇧", "Y"], "Den Mode: Copy Focused Board ID"),
                    item(["Return"], "Den Mode: Duplicate Focused Board"),
                    item(["Shift", "+", "Return"], "Den Mode: New Board from First Sheet; zmx duplicate"),
                    item(["r"], "Den Mode: Rename Board"),
                    item(["-", "/", "="], "Den Mode: Narrow / widen Board"),
                    item(["w", "then", "- / = / 1–9"], "Den Mode: Resize all Boards"),
                    item(["⌘", "+", "/", "-"], "Increase / decrease Current Sheet size"),
                    item(["⌘", "0"], "Reset Current Sheet size"),
                    item(["f"], "Den Mode: Toggle maximized Board"),
                    item(["c"], "Den Mode: Center Focused Board"),
                    item(["b"], "Den Mode: Save Board as Essential"),
                    item(["⌘", "W"], "Remove Focused Board"),
                    item(["d"], "Den Mode: Remove Focused Board and focus next Board"),
                    item(["x"], "Den Mode: Remove Focused Board and focus previous Board"),
                    item(["u"], "Den Mode: Restore Removed Board"),
                ]),
            ShortcutGuideSection(
                title: "Desk",
                items: [
                    item(["⇧", "N"], "Den Mode: New Desk"),
                    item(["p"], "Den Mode: Save Desk as Preset"),
                    item(["⇧", "P"], "Den Mode: Replace Desk from Preset"),
                    item(["⌃", "P"], "Den Mode: Manage Desk Presets"),
                    item(["⇧", "R"], "Den Mode: Rename Desk"),
                    item(["⇧", "D"], "Den Mode: Delete Focused Desk"),
                ]),
            ShortcutGuideSection(
                title: "Sheet",
                items: [
                    item(["⌘", "L"], "Edit Focused Board Link"),
                    item(["[", "/", "]"], "Den Mode: Back / forward Sheet"),
                    item(["⇧", "[", "/", "⇧", "]"], "Den Mode: First / latest Sheet"),
                    item(["t"], "Den Mode: Pause / resume Sheet Navigation for Focused Board"),
                    item(["⌘", "R"], "Reload Current Sheet"),
                    item(["⇧", "⌘", "R"], "Hard Reload Current Sheet"),
                    item(["⌘", "⌥", "⇧", "R"], "Reload Focused Desk Sheets"),
                    item(["⌃", "s"], "Den Mode: Copy Current Sheet screenshot to clipboard"),
                    item(["s"], "Den Mode: Capture Current Sheet Screenshot"),
                    item(["⌘", "⌥", "I"], "Inspect Current Sheet"),
                ]),
            ShortcutGuideSection(
                title: "Drawer",
                items: [
                    item(["Tab"], "Den Mode: Toggle Drawer"),
                    item(["/"], "Search Drawer Items in Den Mode"),
                    item(["↑", "/", "↓", "or", "k", "/", "j"], "Select Drawer Item"),
                    item(["Return"], "Toggle Drawer Preview"),
                    item(["f"], "Toggle Floating / Bottom presentation"),
                    item(["p"], "Place as Board"),
                    item(["a"], "Den Mode: Keep Current Sheet in Drawer"),
                    item(["a", "then", "link hint"], "Den Mode: Keep link in Drawer with Sheet Navigation"),
                    item(["d", "or", "Delete"], "Discard Drawer Item and focus next"),
                    item(["x"], "Discard Drawer Item and focus previous"),
                    item(["⌘", "W"], "Discard selected Drawer Item and focus next"),
                    item(["u"], "Restore discarded Drawer Item"),
                    item(["Tab"], "Close Drawer in Den Mode"),
                    item(["⌃", "Escape"], "Close Drawer"),
                    item(["Escape"], "Exit Den Mode / close Drawer"),
                ]),
            ShortcutGuideSection(
                title: "Overview",
                items: [
                    item(["o"], "Den Mode: Overview"),
                    item(["/"], "Search / Filter"),
                    item(["←", "/", "→", "or", "h", "/", "l"], "Select Board"),
                    item(["↑", "/", "↓", "or", "j", "/", "k"], "Select Desk"),
                    item(["Shift", "+", "movement"], "Move selected Board"),
                    item(["Return"], "Enter selection"),
                    item(["Escape"], "Return to Den Mode"),
                ]),
            ShortcutGuideSection(
                title: "zmx Sessions",
                items: [
                    item(["/"], "Filter Sessions"),
                    item(["↑", "/", "↓", "or", "k", "/", "j"], "Focus previous / next Session"),
                    item(["Space"], "Mark / unmark Focused Session"),
                    item(["⌘", "A"], "Mark all visible Sessions"),
                    item(["Return"], "Open Focused Session as a Board"),
                    item(["x", "/", "Delete"], "End marked or Focused Sessions"),
                    item(["r"], "Refresh Sessions"),
                    item(["Escape"], "Exit filtering, clear marks or query, then close"),
                ]),
            ShortcutGuideSection(
                title: "App and Presentation",
                items: [
                    item(["⌃", "⌘", "P"], "Open Profile panel"),
                    item(["i"], "Den Mode: Show Notifications"),
                    item(["↑", "/", "↓"], "Den Mode: Select notification; Return opens it"),
                    customItem(.toggleBoardRail),
                    item(["z"], "Den Mode: Toggle Zen View"),
                    item(["⇧", "F"], "Den Mode: Toggle Focus Mode"),
                    item([","], "Den Mode: Open Settings"),
                    item(["?"], "Den Mode: Keyboard Shortcuts"),
                    item(["⇧", "Escape"], "Board Activity"),
                    item(["⇧", "⌘", "W"], "Close Profile Window"),
                    item(["⌘", "Q"], "Quit Den Browser"),
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .frame(height: 30, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.label), \(item.accessibilityKeys)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct ShortcutChip: View {
    let tokens: [String]
    var width: CGFloat?
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

struct ShortcutGuideSection: Identifiable {
    let title: String
    let items: [ShortcutGuideItem]
    var id: String { title }

    func filtered(matching query: String) -> Self? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return self }
        guard !title.localizedStandardContains(query) else { return self }

        let matchingItems = items.filter { $0.matches(query) }
        guard !matchingItems.isEmpty else { return nil }
        return Self(title: title, items: matchingItems)
    }
}

struct ShortcutGuideItem: Identifiable {
    let keys: [String]
    let label: String
    let accessibilityKeys: String
    var id: String { titleKey }
    private var titleKey: String { "\(label)-\(keys.joined())" }

    func matches(_ query: String) -> Bool {
        label.localizedStandardContains(query)
            || keys.joined(separator: " ").localizedStandardContains(query)
            || accessibilityKeys.localizedStandardContains(query)
    }
}
