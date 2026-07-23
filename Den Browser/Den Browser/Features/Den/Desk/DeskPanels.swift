import SwiftUI

struct NewDeskPanel: View {
    @Environment(DenStore.self) private var store
    @Binding var selectedDeskPreset: DeskPresetSelection
    @Binding var activeDeskPreset: DeskPresetSelection
    @Binding var query: String
    @Binding var isManaging: Bool
    @Binding var isChoosing: Bool
    @Binding var didAttemptCreation: Bool
    @Binding var newDeskLabel: String
    @FocusState.Binding var isSearchFocused: Bool
    @FocusState.Binding var isLabelFocused: Bool

    let selectedBoards: [DeskPresetBoard]
    let presetLabel: String
    let boardCountLabel: String
    let trimmedLabel: String
    let description: String
    let onConfirmPreset: (DeskPresetSelection) -> Void
    let onBeginSelection: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: store.isDeskPresetManagementPresented ? "bookmark" : "rectangle.stack.badge.plus")
                    .foregroundStyle(.secondary)
                Text(store.isDeskPresetManagementPresented ? "Manage Presets" : "New Desk")
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(height: 38)

            if isChoosing {
                DeskPresetPicker(
                    selection: $activeDeskPreset,
                    query: $query,
                    isManaging: $isManaging,
                    isSearchFocused: $isSearchFocused,
                    onConfirm: onConfirmPreset)
            } else {
                HStack(spacing: 10) {
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

                TextField("Desk label", text: $newDeskLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16, weight: .medium))
                    .focused($isLabelFocused)
                    .onSubmit(onCreate)
                    .onKeyPress(phases: .down) { keyPress in
                        let isBackTab = keyPress.key == .tab || keyPress.characters == "\u{19}"
                        guard isBackTab, keyPress.modifiers.contains(.shift) else { return .ignored }
                        onBeginSelection()
                        return .handled
                    }

                HStack(spacing: 12) {
                    if didAttemptCreation && trimmedLabel.isEmpty {
                        Text("Enter a desk label").foregroundStyle(.red)
                    } else {
                        Text(description).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Create", action: onCreate)
                        .buttonStyle(.glassProminent)
                        .disabled(trimmedLabel.isEmpty || !store.canCreateDesk)
                }
                .font(.system(size: 12))
            }
        }
        .padding(16)
        .frame(width: 620)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            selectedDeskPreset = .builtIn(.empty)
            activeDeskPreset = .builtIn(.empty)
            newDeskLabel = BuiltInDeskPreset.empty.label
            query = ""
            isManaging = store.isDeskPresetManagementPresented
            isChoosing = true
            didAttemptCreation = false
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark").foregroundStyle(.secondary)
                Text("Save Desk as Preset").font(.system(size: 17, weight: .semibold))
            }
            TextField("Preset label", text: $label)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(onSave)
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
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "pencil").foregroundStyle(.secondary)
                TextField("Rename desk", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isFocused)
                    .onSubmit { store.renameFocusedDesk(to: text) }
            }
            .frame(height: 38)
            HStack(spacing: 12) {
                Text("Press Return to confirm, Escape to cancel").foregroundStyle(.secondary)
                Spacer()
                Text("R in Den Mode").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            text = store.focusedDesk?.label ?? ""
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand { store.hideRenameDeskPanel() }
    }
}
