import SFSafeSymbols
import SwiftUI

struct DeskPresetManagementPanel: View {
    let isStandalone: Bool
    let onClose: () -> Void

    @Environment(DenStore.self) private var store
    @State private var query = ""
    @State private var selectedPresetID: UUID?
    @State private var editingPresetID: UUID?
    @State private var editingLabel = ""
    @State private var editingSelection: TextSelection?
    @State private var editingError: String?
    @State private var scrollPosition = ScrollPosition()
    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedEditingID: UUID?

    private var filteredPresets: [PersonalDeskPreset] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return store.deskPresets }
        return store.deskPresets.filter {
            $0.id == editingPresetID || DeskPresetSearch.score(query: query, label: $0.label, boards: $0.boards) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DenPanelHeader(systemSymbol: .bookmark) {
                Text("Manage Presets")
                    .font(.headline)
                Spacer()
                if isStandalone {
                    DenCloseButton(label: "Close Presets", action: onClose)
                } else {
                    Button(action: onClose) {
                        Image(systemSymbol: .chevronLeft)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to Desk Presets")
                    .help("Back to Desk Presets")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField(text: $query, prompt: Text("Filter presets")) {
                    Text("Search Personal Desk Presets")
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onSubmit { TextInputComposition.performUnlessActive(beginRenameSelected) }
                .onKeyPress(.escape) {
                    guard !TextInputComposition.isActive else { return .ignored }
                    if editingPresetID != nil {
                        cancelEdit()
                    } else {
                        onClose()
                    }
                    return .handled
                }

                if filteredPresets.isEmpty {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("No Personal Desk Presets", systemSymbol: .bookmark)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredPresets) { preset in
                                presetRow(preset)
                                    .id(preset.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition($scrollPosition, anchor: .center)
                    .scrollIndicators(.never)
                    .frame(maxHeight: 220)
                }
            }
            .deskPresetArrowNavigation(isEditing: editingPresetID != nil) { moveSelection(by: $0) }
        }
        .denPanel(width: DenPanelLayout.wideWidth)
        .onAppear {
            ensureSelectedPreset()
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: query) { _, _ in ensureSelectedPreset() }
        .onChange(of: store.deskPresets.map(\.id)) { _, _ in
            if let editingPresetID, !store.deskPresets.contains(where: { $0.id == editingPresetID }) {
                cancelEdit()
            }
            ensureSelectedPreset()
        }
        .onChange(of: filteredPresets.map(\.id)) { _, _ in ensureSelectedPreset() }
        .onChange(of: selectedPresetID) { _, id in
            if let id { scrollPosition.scrollTo(id: id, anchor: .center) }
        }
        .onExitCommand {
            if editingPresetID != nil {
                cancelEdit()
            } else {
                onClose()
            }
        }
        .onDisappear(perform: clearEditState)
    }

    private func presetRow(_ preset: PersonalDeskPreset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if editingPresetID == preset.id {
                    TextField(
                        text: $editingLabel,
                        selection: $editingSelection,
                        prompt: Text("Preset label")
                    ) {
                        Text("Rename \(preset.label)")
                    }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedEditingID, equals: preset.id)
                    .onSubmit { TextInputComposition.performUnlessActive(saveEdit) }
                    .onKeyPress(.escape) {
                        guard !TextInputComposition.isActive else { return .ignored }
                        cancelEdit()
                        return .handled
                    }
                    .onAppear {
                        editingSelection = TextSelection(range: editingLabel.startIndex..<editingLabel.endIndex)
                        DispatchQueue.main.async { focusedEditingID = preset.id }
                    }
                } else {
                    Button {
                        selectedPresetID = preset.id
                        DispatchQueue.main.async { isSearchFocused = true }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.label)
                                .lineLimit(1)
                            Text(boardCountLabel(preset.boards.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selectedPresetID == preset.id ? "Selected" : "")
                }
                Spacer(minLength: 0)
                if editingPresetID == preset.id {
                    Button(action: saveEdit) {
                        Image(systemSymbol: .checkmark)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save Preset Label")
                    Button(action: cancelEdit) {
                        Image(systemSymbol: .xmark)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel Rename")
                } else {
                    Button {
                        selectedPresetID = preset.id
                        beginEdit(preset)
                    } label: {
                        Image(systemSymbol: .pencil)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename \(preset.label)")
                }
                Button(role: .destructive) {
                    store.requestDeskPresetDeletion(preset.id)
                } label: {
                    Image(systemSymbol: .trash)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(preset.label)")
            }
            if editingPresetID == preset.id, let editingError {
                DenValidationMessage(editingError)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(selectedPresetID == preset.id ? 0.11 : 0.055),
            in: RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
                .strokeBorder(
                    selectedPresetID == preset.id ? Color.accentColor.opacity(0.8) : Color.clear,
                    lineWidth: 1
                )
        }
    }

    private func moveSelection(by offset: Int) {
        selectedPresetID = DeskPresetSelectionNavigation.next(
            selectedPresetID,
            among: filteredPresets.map(\.id),
            by: offset
        )
    }

    private func ensureSelectedPreset() {
        let ids = filteredPresets.map(\.id)
        if let selectedPresetID, ids.contains(selectedPresetID) { return }
        selectedPresetID = ids.first
    }

    private func beginRenameSelected() {
        guard let preset = filteredPresets.first(where: { $0.id == selectedPresetID }) else { return }
        beginEdit(preset)
    }

    private func beginEdit(_ preset: PersonalDeskPreset) {
        editingPresetID = preset.id
        editingLabel = preset.label
        editingError = nil
    }

    private func cancelEdit() {
        editingPresetID = nil
        editingError = nil
        focusedEditingID = nil
        ensureSelectedPreset()
        DispatchQueue.main.async { isSearchFocused = true }
    }

    private func clearEditState() {
        editingPresetID = nil
        editingError = nil
        focusedEditingID = nil
    }

    private func saveEdit() {
        guard let editingPresetID else { return }
        switch store.renameDeskPreset(editingPresetID, to: editingLabel) {
        case .renamed, .unchanged:
            cancelEdit()
        case .invalidLabel:
            editingError = "Enter a Preset label"
        case .reservedLabel:
            editingError = "Built-in Desk Preset labels are reserved"
        case .duplicateLabel:
            editingError = "A Personal Desk Preset already uses this label"
        case .unavailable:
            cancelEdit()
        }
    }

    private func boardCountLabel(_ count: Int) -> String {
        count == 1 ? "1 Board" : "\(count) Boards"
    }
}
