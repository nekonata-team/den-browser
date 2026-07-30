import SwiftUI

struct NewDeskPanel: View {
    @Environment(DenStore.self) private var store
    @Binding var selectedDeskPreset: DeskPresetSelection
    @Binding var activeDeskPreset: DeskPresetSelection
    @Binding var query: String
    @Binding var isManaging: Bool
    @Binding var isChoosing: Bool
    @Binding var didAttemptAction: Bool
    @Binding var newDeskLabel: String
    @Binding var newDeskLabelSelection: TextSelection?
    @FocusState.Binding var isSearchFocused: Bool
    @FocusState.Binding var isLabelFocused: Bool

    let selectedBoards: [DeskPresetBoard]
    let presetLabel: String
    let boardCountLabel: String
    let trimmedLabel: String
    let description: String
    let onConfirmPreset: (DeskPresetSelection) -> Void
    let onBeginSelection: () -> Void
    let onSubmit: () -> Void

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
                    selection: $activeDeskPreset,
                    query: $query,
                    isManaging: $isManaging,
                    allowsEmptyPreset: !store.isReplaceDeskPanelPresented,
                    isSearchFocused: $isSearchFocused,
                    onConfirm: onConfirmPreset)
            } else {
                HStack(spacing: DenPanelLayout.controlSpacing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presetLabel).font(.headline)
                        Text(boardCountLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change Preset", action: onBeginSelection).buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous))

                DeskPresetPreview(boards: selectedBoards)

                TextField("Desk label", text: $newDeskLabel, selection: $newDeskLabelSelection)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.weight(.medium))
                    .focused($isLabelFocused)
                    .onSubmit { TextInputComposition.performUnlessActive(onSubmit) }
                    .onKeyPress(phases: .down) { keyPress in
                        let isBackTab = keyPress.key == .tab || keyPress.characters == "\u{19}"
                        guard
                            isBackTab,
                            keyPress.modifiers.contains(.shift),
                            !TextInputComposition.isActive
                        else { return .ignored }
                        onBeginSelection()
                        return .handled
                    }

                HStack(spacing: DenPanelLayout.contentSpacing) {
                    if didAttemptAction && trimmedLabel.isEmpty {
                        Text("Enter a desk label").foregroundStyle(.red)
                    } else {
                        Text(description).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.isReplaceDeskPanelPresented ? "Replace Desk" : "Create", action: onSubmit)
                        .buttonStyle(.glassProminent)
                        .disabled(
                            trimmedLabel.isEmpty
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
            activeDeskPreset = initialPreset
            newDeskLabel =
                store.isReplaceDeskPanelPresented ? BuiltInDeskPreset.chatGPT.label : BuiltInDeskPreset.empty.label
            query = ""
            isManaging = store.isDeskPresetManagementPresented
            isChoosing = true
            didAttemptAction = false
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onExitCommand {
            if isChoosing { store.hideNewDeskPanel() } else { onBeginSelection() }
        }
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
            TextField("Preset label", text: $label)
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
                TextField("Rename desk", text: $text)
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
