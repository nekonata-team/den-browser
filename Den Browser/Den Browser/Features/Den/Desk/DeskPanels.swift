import SwiftUI

struct NewDeskPanel: View {
    @Environment(DenStore.self) private var store
    @State private var selectedDeskPreset: DeskPresetSelection = .builtIn(.empty)
    @State private var query = ""
    @State private var isManaging = false
    @State private var isChoosing = true
    @State private var didAttemptAction = false
    @State private var newDeskLabel = ""
    @State private var newDeskLabelSelection: TextSelection?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isLabelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DenPanelHeader(
                systemImage: store.isDeskPresetManagementPresented
                    ? "bookmark"
                    : store.isReplaceDeskPanelPresented
                        ? "rectangle.stack.badge.minus" : "rectangle.stack.badge.plus"
            ) {
                Text(
                    store.isDeskPresetManagementPresented
                        ? "Manage Presets"
                        : store.isReplaceDeskPanelPresented ? "Replace Desk" : "New Desk"
                )
                .font(.headline)
            }

            if isChoosing {
                DeskPresetPicker(
                    initialSelection: selectedDeskPreset,
                    query: $query,
                    isManaging: $isManaging,
                    allowsEmptyPreset: !store.isReplaceDeskPanelPresented,
                    isSearchFocused: $isSearchFocused,
                    onConfirm: confirmDeskPreset)
            } else {
                HStack(spacing: DenPanelLayout.controlSpacing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedDeskPresetLabel).font(.headline)
                        Text(boardCountLabel(selectedDeskPresetBoards.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change Preset", action: beginDeskPresetSelection).buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous))

                DeskPresetPreview(boards: selectedDeskPresetBoards)

                TextField(
                    text: $newDeskLabel,
                    selection: $newDeskLabelSelection,
                    prompt: Text("e.g. Research")
                ) {
                    Text("Desk label")
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.body.weight(.medium))
                .focused($isLabelFocused)
                .onSubmit { TextInputComposition.performUnlessActive(submitDeskPreset) }
                .onKeyPress(phases: .down) { keyPress in
                    let isBackTab = keyPress.key == .tab || keyPress.characters == "\u{19}"
                    guard
                        isBackTab,
                        keyPress.modifiers.contains(.shift),
                        !TextInputComposition.isActive
                    else { return .ignored }
                    beginDeskPresetSelection()
                    return .handled
                }

                HStack(spacing: DenPanelLayout.contentSpacing) {
                    if didAttemptAction && trimmedNewDeskLabel.isEmpty {
                        Text("Enter a desk label").foregroundStyle(.red)
                    } else {
                        Text(newDeskPanelDescription).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(
                        store.isReplaceDeskPanelPresented ? "Replace Desk" : "Create",
                        action: submitDeskPreset
                    )
                    .buttonStyle(.glassProminent)
                    .disabled(
                        trimmedNewDeskLabel.isEmpty
                            || (!store.isReplaceDeskPanelPresented && !store.canCreateDesk))
                }
                .font(.caption)
            }
        }
        .denPanel(width: DenPanelLayout.wideWidth)
        .onAppear {
            let initialPreset: DeskPresetSelection =
                store.isReplaceDeskPanelPresented ? .builtIn(.chatGPT) : .builtIn(.empty)
            selectedDeskPreset = initialPreset
            newDeskLabel =
                store.isReplaceDeskPanelPresented ? BuiltInDeskPreset.chatGPT.label : BuiltInDeskPreset.empty.label
            query = ""
            isManaging = store.isDeskPresetManagementPresented
            isChoosing = true
            didAttemptAction = false
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: store.deskPresets.map(\.id)) { _, _ in
            ensureSelectedPresetExists()
        }
        .onExitCommand {
            if isChoosing { store.hideNewDeskPanel() } else { beginDeskPresetSelection() }
        }
    }

    private var trimmedNewDeskLabel: String {
        newDeskLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var newDeskPanelDescription: String {
        if store.isReplaceDeskPanelPresented {
            return store.focusedDesk?.boards.isEmpty == false
                ? "Existing Boards will be removed after confirmation"
                : "Applies this arrangement to the focused Desk"
        }
        return store.canCreateDesk ? "New desk opens after the focused desk" : "A Den can contain up to 10 desks"
    }

    private var selectedDeskPresetBoards: [DeskPresetBoard] {
        switch selectedDeskPreset {
        case .builtIn(let preset):
            preset.boards
        case .personal(let id):
            store.deskPresets.first(where: { $0.id == id })?.boards ?? []
        }
    }

    private var selectedDeskPresetLabel: String {
        switch selectedDeskPreset {
        case .builtIn(let preset):
            preset.label
        case .personal(let id):
            store.deskPresets.first(where: { $0.id == id })?.label ?? BuiltInDeskPreset.empty.label
        }
    }

    private func boardCountLabel(_ count: Int) -> String {
        count == 1 ? "1 Board" : "\(count) Boards"
    }

    private func submitDeskPreset() {
        didAttemptAction = true
        guard !trimmedNewDeskLabel.isEmpty else { return }

        if store.isReplaceDeskPanelPresented {
            let result: DeskReplacementResult?
            switch selectedDeskPreset {
            case .builtIn(let preset):
                result = store.replaceFocusedDesk(label: newDeskLabel, preset: preset)
            case .personal(let id):
                result = store.replaceFocusedDesk(label: newDeskLabel, personalPresetID: id)
            }
            if result == .applied {
                resetDeskPresetPanel()
            }
            return
        }

        switch selectedDeskPreset {
        case .builtIn(let preset):
            store.createDesk(label: newDeskLabel, preset: preset)
        case .personal(let id):
            store.createDesk(label: newDeskLabel, personalPresetID: id)
        }
        resetDeskPresetPanel()
    }

    private func resetDeskPresetPanel() {
        newDeskLabel = ""
        selectedDeskPreset = .builtIn(.empty)
        didAttemptAction = false
    }

    private func confirmDeskPreset(_ selection: DeskPresetSelection) {
        let label = deskPresetLabel(for: selection)
        selectedDeskPreset = selection
        newDeskLabel = label
        newDeskLabelSelection = TextSelection(range: label.startIndex..<label.endIndex)
        isChoosing = false
        didAttemptAction = false
        DispatchQueue.main.async { isLabelFocused = true }
    }

    private func beginDeskPresetSelection() {
        isChoosing = true
        isManaging = false
        DispatchQueue.main.async { isSearchFocused = true }
    }

    private func deskPresetLabel(for selection: DeskPresetSelection) -> String {
        switch selection {
        case .builtIn(let preset):
            preset.label
        case .personal(let id):
            store.deskPresets.first(where: { $0.id == id })?.label ?? BuiltInDeskPreset.empty.label
        }
    }

    private func ensureSelectedPresetExists() {
        guard case .personal(let id) = selectedDeskPreset,
            !store.deskPresets.contains(where: { $0.id == id })
        else { return }

        let fallback: DeskPresetSelection =
            store.isReplaceDeskPanelPresented ? .builtIn(.chatGPT) : .builtIn(.empty)
        selectedDeskPreset = fallback
        newDeskLabel = deskPresetLabel(for: fallback)
    }
}

struct SaveDeskPresetPanel: View {
    @Environment(DenStore.self) private var store
    @Binding var label: String
    @Binding var message: String?
    @FocusState.Binding var isFocused: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            HStack(spacing: DenPanelLayout.controlSpacing) {
                Image(systemName: "bookmark").foregroundStyle(.secondary)
                Text("Save Desk as Preset").font(.headline)
            }
            TextField(
                text: $label,
                prompt: Text("e.g. Daily research")
            ) {
                Text("Preset label")
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit { TextInputComposition.performUnlessActive(onSave) }
            DeskPresetPreview(boards: store.focusedDesk?.boards.map(DeskPresetBoard.init) ?? [])
            HStack {
                Text(message ?? "Captures the current Board arrangement")
                    .font(.caption)
                    .foregroundStyle(message == nil ? Color.secondary : Color.red)
                Spacer()
                Button("Save Preset", action: onSave)
                    .buttonStyle(.glassProminent)
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .denPanel()
        .onAppear {
            label = store.focusedDesk?.label ?? ""
            message = nil
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand { store.hideSaveDeskPresetPanel() }
    }
}

struct RenameDeskPanel: View {
    @Environment(DenStore.self) private var store
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemImage: "pencil") {
                TextField(
                    text: $text,
                    prompt: Text("Desk label")
                ) {
                    Text("Rename desk")
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .focused($isFocused)
                .onSubmit {
                    TextInputComposition.performUnlessActive {
                        store.renameFocusedDesk(to: text)
                    }
                }
            }
            HStack(spacing: DenPanelLayout.contentSpacing) {
                Text("Press Return to confirm, Escape to cancel").foregroundStyle(.secondary)
                Spacer()
                Text("R in Den Mode").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .denPanel()
        .onAppear {
            text = store.focusedDesk?.label ?? ""
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand { store.hideRenameDeskPanel() }
    }
}
