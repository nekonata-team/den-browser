public import AppKit
public import DenDomain
public import DenPresentationModels
import SFSafeSymbols
public import SwiftUI

public struct NewDeskPanel: View {
    let profileColor: Color
    var boardHeight: CGFloat = DenLayout.fallbackBoardHeight

    private let facing: (UUID, Int) -> NSImage?
    private let loadFacings: (UUID, Int) async -> Void
    @Environment(DenWindowModel.self) private var windowModel
    @State private var selectedDeskPreset: DeskPresetSelection = .builtIn(.empty)
    @State private var query = ""
    @State private var isManagementPresented = false
    @State private var isChoosing = true
    @State private var didAttemptAction = false
    @State private var newDeskLabel = ""
    @State private var newDeskLabelSelection: TextSelection?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isLabelFocused: Bool

    public init(
        profileColor: Color, boardHeight: CGFloat = DenLayout.fallbackBoardHeight,
        facing: @escaping (UUID, Int) -> NSImage?, loadFacings: @escaping (UUID, Int) async -> Void
    ) {
        self.profileColor = profileColor
        self.boardHeight = boardHeight
        self.facing = facing
        self.loadFacings = loadFacings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(
                systemSymbol: windowModel.isReplaceDeskPanelPresented
                    ? .rectangleStackBadgeMinus : .rectangleStackBadgePlus
            ) {
                Text(windowModel.isReplaceDeskPanelPresented ? "Replace Desk" : "New Desk")
                    .font(.headline)
            }

            if isChoosing {
                DeskPresetPicker(
                    profileColor: profileColor,
                    initialSelection: selectedDeskPreset,
                    query: $query,
                    isManagementPresented: $isManagementPresented,
                    allowsEmptyPreset: !windowModel.isReplaceDeskPanelPresented,
                    isSearchFocused: $isSearchFocused,
                    boardHeight: boardHeight,
                    facing: facing, loadFacings: loadFacings, onConfirm: confirmDeskPreset)
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

                DeskPresetPreview(
                    boards: selectedDeskPresetBoards,
                    boardHeight: boardHeight,
                    facingForBoard: { index, _ in
                        if case .personal(let id) = selectedDeskPreset {
                            return facing(id, index)
                        }
                        return nil
                    }
                )

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
                        DenValidationMessage("Enter a desk label")
                    } else {
                        DenPanelHint(newDeskPanelDescription)
                    }
                    Spacer()
                    Button(
                        windowModel.isReplaceDeskPanelPresented ? "Replace Desk" : "Create",
                        action: submitDeskPreset
                    )
                    .buttonStyle(.glassProminent)
                    .disabled(
                        trimmedNewDeskLabel.isEmpty
                            || (!windowModel.isReplaceDeskPanelPresented && !windowModel.desks.canCreateDesk))
                }
                .font(.caption)
            }
        }
        .denPanel(width: DenPanelLayout.wideWidth)
        .opacity(isManagementPresented ? 0 : 1)
        .disabled(isManagementPresented)
        .accessibilityHidden(isManagementPresented)
        .overlay {
            if isManagementPresented {
                DeskPresetManagementPanel(
                    isStandalone: false, profileColor: profileColor,
                    presets: windowModel.desks.deskPresets,
                    boardHeight: boardHeight,
                    renamePreset: windowModel.deskPresetActions.rename,
                    requestDeletion: windowModel.deskPresetActions.requestDeletion, facing: facing,
                    loadFacings: loadFacings
                ) {
                    isManagementPresented = false
                    DispatchQueue.main.async { isSearchFocused = true }
                }
                .zIndex(1)
            }
        }
        .onAppear {
            let initialPreset: DeskPresetSelection =
                windowModel.isReplaceDeskPanelPresented ? .builtIn(.chatGPT) : .builtIn(.empty)
            selectedDeskPreset = initialPreset
            newDeskLabel =
                windowModel.isReplaceDeskPanelPresented
                ? BuiltInDeskPreset.chatGPT.label : BuiltInDeskPreset.empty.label
            query = ""
            isManagementPresented = false
            isChoosing = true
            didAttemptAction = false
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: windowModel.desks.deskPresets.map(\.id)) { _, _ in
            ensureSelectedPresetExists()
        }
        .task(id: selectedDeskPreset) {
            if case .personal(let id) = selectedDeskPreset {
                await loadFacings(id, selectedDeskPresetBoards.count)
            }
        }
        .onExitCommand {
            guard !isManagementPresented else { return }
            if isChoosing {
                windowModel.hideNewDeskPanel()
            } else {
                beginDeskPresetSelection()
            }
        }
    }

    private var trimmedNewDeskLabel: String {
        newDeskLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var newDeskPanelDescription: String {
        if windowModel.isReplaceDeskPanelPresented {
            return windowModel.desks.focusedDesk?.boards.isEmpty == false
                ? "Existing Boards will be removed after confirmation"
                : "Applies this arrangement to the focused Desk"
        }
        return windowModel.desks.canCreateDesk
            ? "New desk opens after the focused desk" : "A Den can contain up to 10 desks"
    }

    private var selectedDeskPresetBoards: [DeskPresetBoard] {
        switch selectedDeskPreset {
        case .builtIn(let preset):
            preset.boards
        case .personal(let id):
            windowModel.desks.deskPresets.first(where: { $0.id == id })?.boards ?? []
        case .newDesk:
            []
        }
    }

    private var selectedDeskPresetLabel: String {
        switch selectedDeskPreset {
        case .builtIn(let preset):
            preset.label
        case .personal(let id):
            windowModel.desks.deskPresets.first(where: { $0.id == id })?.label ?? BuiltInDeskPreset.empty.label
        case .newDesk(let label):
            label
        }
    }

    private func boardCountLabel(_ count: Int) -> String {
        count == 1 ? "1 Board" : "\(count) Boards"
    }

    private func submitDeskPreset() {
        guard windowModel.isNewDeskPanelPresented, !isChoosing else { return }
        didAttemptAction = true
        guard !trimmedNewDeskLabel.isEmpty else { return }

        if windowModel.isReplaceDeskPanelPresented {
            let result = windowModel.desks.replaceDesk(label: newDeskLabel, selection: selectedDeskPreset)
            if result == .applied {
                resetDeskPresetPanel()
            }
            return
        }

        windowModel.desks.createDesk(label: newDeskLabel, selection: selectedDeskPreset)
        resetDeskPresetPanel()
    }

    private func resetDeskPresetPanel() {
        newDeskLabel = ""
        selectedDeskPreset = .builtIn(.empty)
        didAttemptAction = false
    }

    private func confirmDeskPreset(_ selection: DeskPresetSelection) {
        guard windowModel.isNewDeskPanelPresented, isChoosing else { return }
        if case .newDesk(let label) = selection {
            guard windowModel.desks.canCreateDesk else {
                presentDeskDetails(for: selection, label: label)
                return
            }
            windowModel.desks.createDesk(label: label, selection: .builtIn(.empty))
            resetDeskPresetPanel()
            return
        }
        presentDeskDetails(for: selection, label: deskPresetLabel(for: selection))
    }

    private func presentDeskDetails(for selection: DeskPresetSelection, label: String) {
        selectedDeskPreset = selection
        newDeskLabel = label
        newDeskLabelSelection = TextSelection(range: label.startIndex..<label.endIndex)
        isChoosing = false
        didAttemptAction = false
        DispatchQueue.main.async { isLabelFocused = true }
    }

    private func beginDeskPresetSelection() {
        isChoosing = true
        DispatchQueue.main.async { isSearchFocused = true }
    }

    private func deskPresetLabel(for selection: DeskPresetSelection) -> String {
        switch selection {
        case .builtIn(let preset):
            preset.label
        case .personal(let id):
            windowModel.desks.deskPresets.first(where: { $0.id == id })?.label ?? BuiltInDeskPreset.empty.label
        case .newDesk(let label):
            label
        }
    }

    private func ensureSelectedPresetExists() {
        guard case .personal(let id) = selectedDeskPreset,
            !windowModel.desks.deskPresets.contains(where: { $0.id == id })
        else { return }

        let fallback: DeskPresetSelection =
            windowModel.isReplaceDeskPanelPresented ? .builtIn(.chatGPT) : .builtIn(.empty)
        selectedDeskPreset = fallback
        newDeskLabel = deskPresetLabel(for: fallback)
    }
}

public struct SaveDeskPresetPanel: View {
    let initialLabel: String
    let previewBoards: [DeskPresetBoard]
    var boardHeight: CGFloat = DenLayout.fallbackBoardHeight
    let savePreset: (String) -> DeskPresetSaveResult
    let onClose: () -> Void
    private let facing: (Int) -> NSImage?
    private let captureFacings: () async -> Void
    @State private var label = ""
    @State private var message: String?
    @FocusState private var isFocused: Bool

    public init(
        initialLabel: String, previewBoards: [DeskPresetBoard], boardHeight: CGFloat = DenLayout.fallbackBoardHeight,
        savePreset: @escaping (String) -> DeskPresetSaveResult, facing: @escaping (Int) -> NSImage?,
        captureFacings: @escaping () async -> Void, onClose: @escaping () -> Void
    ) {
        self.initialLabel = initialLabel
        self.previewBoards = previewBoards
        self.boardHeight = boardHeight
        self.savePreset = savePreset
        self.facing = facing
        self.captureFacings = captureFacings
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .bookmark) {
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
            .onSubmit { TextInputComposition.performUnlessActive(save) }
            DeskPresetPreview(
                boards: previewBoards,
                boardHeight: boardHeight,
                facingForBoard: { index, _ in
                    facing(index)
                }
            )
            HStack {
                if let message {
                    DenValidationMessage(message)
                } else {
                    DenPanelHint("Captures the current Board arrangement")
                }
                Spacer()
                Button("Save Preset", action: save)
                    .buttonStyle(.glassProminent)
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .denPanel()
        .task {
            await captureFacings()
        }
        .onAppear {
            label = initialLabel
            message = nil
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand { onClose() }
    }

    private func save() {
        switch savePreset(label) {
        case .created:
            onClose()
        case .replacementPending:
            message = nil
        case .invalidLabel:
            message = "Enter a Preset label"
        case .emptyDesk:
            message = "A Personal Desk Preset needs at least one Board"
        case .reservedLabel:
            message = "Built-in Desk Preset labels are reserved"
        }
    }
}
