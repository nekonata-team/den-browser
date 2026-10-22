import AppKit
import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

public struct OpenBoardPanel: View {
    private static let maximumVisibleRecentItemCount = 5

    @Environment(BoardEditingModel.self) private var editing
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(OpenBoardModel.self) private var openBoard
    @FocusState private var isFocused: Bool
    @State private var selectedRecentItemID: RecentItem?
    @State private var isClearRecentConfirmationPresented = false

    let profileColor: Color
    let newBoardWidth: Double

    public init(profileColor: Color, newBoardWidth: Double) {
        self.profileColor = profileColor
        self.newBoardWidth = newBoardWidth
    }

    private var filteredRecentItems: [RecentItem] {
        let query = openBoard.input.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(
            editing.recentItems.lazy.filter {
                query.isEmpty || $0.displayText.localizedCaseInsensitiveContains(query)
                    || ($0.title?.localizedCaseInsensitiveContains(query) ?? false)
            }.prefix(Self.maximumVisibleRecentItemCount))
    }

    private var urlTextBinding: Binding<String> {
        Binding(
            get: { openBoard.input },
            set: { openBoard.input = $0 }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .plusRectangleOnRectangle) {
                TextField(
                    text: urlTextBinding,
                    prompt: Text(verbatim: "https://example.com, search, or :terminal / :tutorial")
                ) {
                    Text("Open URL, search, or command")
                }
                .denPanelHeaderField()
                .focused($isFocused)
                .accessibilityIdentifier("open-board-input")
                .onKeyPress(.downArrow) {
                    guard !TextInputComposition.isActive else { return .ignored }
                    moveRecentSelection(by: 1)
                    return filteredRecentItems.isEmpty ? .ignored : .handled
                }
                .onKeyPress(.upArrow) {
                    guard !TextInputComposition.isActive else { return .ignored }
                    moveRecentSelection(by: -1)
                    return filteredRecentItems.isEmpty ? .ignored : .handled
                }
                .onKeyPress(.rightArrow) {
                    guard !TextInputComposition.isActive,
                        let selectedRecentItemID,
                        let selected = filteredRecentItems.first(where: {
                            $0.id == selectedRecentItemID
                        })
                    else { return .ignored }
                    openBoard.input = selected.displayText
                    return .handled
                }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    guard press.modifiers == .option, !TextInputComposition.isActive else { return .ignored }
                    let selected = filteredRecentItems.first { $0.id == selectedRecentItemID }
                    submitBoard(selected?.displayText, inDrawer: true)
                    return .handled
                }
                .onSubmit {
                    TextInputComposition.performUnlessActive {
                        let selected = filteredRecentItems.first { $0.id == selectedRecentItemID }
                        submitBoard(selected?.displayText)
                    }
                }
            }

            if let message = openBoard.message {
                DenValidationMessage(message)
            }

            if !filteredRecentItems.isEmpty {
                HStack {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        isClearRecentConfirmationPresented = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear Recent")
                }

                ForEach(filteredRecentItems) { item in
                    OpenBoardRecentRow(
                        item: item,
                        isSelected: item.id == selectedRecentItemID,
                        matchedEssential: editing.essentials.first { item.matches(essential: $0) },
                        profileColor: profileColor,
                        onOpen: { submitBoard(item.displayText, inDrawer: $0) },
                        onSaveEssential: { windowModel.showSaveEssentialPanel(for: item) },
                        onRemove: { editing.removeRecentItem(item) }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                DenPanelHint("Option–Return or Option-click a Recent Item to open in Drawer")
                DenPanelHint("Use :tutorial for the interactive guide")
                DenPanelHint("Use :terminal [path], :zellij [session], or :zmx [session] for a Terminal Board")
            }
        }
        .denPanel(width: DenPanelLayout.wideWidth)
        .confirmationDialog(
            "Clear all Recent Items?",
            isPresented: $isClearRecentConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear Recent", role: .destructive, action: editing.clearRecent)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all Recent Items from this Profile. Existing Boards and Essentials are kept.")
        }
        .onAppear {
            if let initialURL = openBoard.initialURL {
                openBoard.input = initialURL.absoluteString
            }
            DispatchQueue.main.async { isFocused = true }
        }
        .onChange(of: openBoard.input) { _, newValue in
            selectedRecentItemID = nil
            openBoard.message = nil
            if isFocused {
                TextInputComposition.syncActiveFieldEditor(to: newValue)
            }
        }
        .onChange(of: filteredRecentItems) { _, items in
            if let selectedRecentItemID, !items.contains(selectedRecentItemID) {
                self.selectedRecentItemID = nil
            }
        }
        .onExitCommand {
            windowModel.hideOpenBoardPanel()
            editing.restoreFocusedFirstResponder()
        }
    }

    private func submitBoard(_ input: String? = nil, inDrawer: Bool = false) {
        if inDrawer {
            openBoard.submitToDrawer(input)
        } else {
            openBoard.submit(input, preferredWidth: newBoardWidth)
        }
        finishOpeningBoardIfNeeded()
    }

    private func finishOpeningBoardIfNeeded() {
        guard !windowModel.isOpenBoardPanelPresented else { return }
        openBoard.clearDraft()
    }

    private func moveRecentSelection(by offset: Int) {
        selectedRecentItemID = SelectionNavigation.next(
            selectedRecentItemID,
            among: filteredRecentItems.map(\.id),
            by: offset
        )
    }
}

private struct OpenBoardRecentRow: View {
    let item: RecentItem
    let isSelected: Bool
    let matchedEssential: Essential?
    let profileColor: Color
    let onOpen: (Bool) -> Void
    let onSaveEssential: () -> Void
    let onRemove: () -> Void

    public var body: some View {
        HStack(spacing: DenPanelLayout.controlSpacing) {
            Button {
                onOpen(NSEvent.modifierFlags.contains(.option))
            } label: {
                HStack(spacing: DenPanelLayout.controlSpacing) {
                    recentItemIcon
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title ?? item.displayText)
                            .lineLimit(1)
                            .truncationMode(item.title == nil ? .middle : .tail)
                        if item.title != nil, case .url(let url, _) = item {
                            Text(url.host ?? url.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a new Board. Option click opens in Drawer.")

            if let matchedEssential {
                HStack(spacing: 4) {
                    ShortcutChip(tokens: [matchedEssential.displayKey])
                    Image(systemSymbol: .sparkles)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .help("Essential: \(matchedEssential.name) [\(matchedEssential.displayKey)]")
                .accessibilityLabel("Essential: \(matchedEssential.name), key \(matchedEssential.displayKey)")
            } else {
                Button(action: onSaveEssential) {
                    Image(systemSymbol: .sparkles)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Save as Essential…")
                .accessibilityLabel("Save as Essential…")
            }

            Button(role: .destructive, action: onRemove) {
                Image(systemSymbol: .trash)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove from Recent")
            .accessibilityLabel("Remove from Recent")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: item.title == nil ? 30 : 38)
        .denSelectionHighlight(isSelected, profileColor: profileColor)
        .contextMenu {
            if let matchedEssential {
                Button {
                } label: {
                    Label("Saved as Essential [\(matchedEssential.displayKey)]", systemSymbol: .sparkles)
                }
                .disabled(true)
            } else {
                Button(action: onSaveEssential) {
                    Label("Save as Essential…", systemSymbol: .sparkles)
                }
            }

            Divider()

            Button(role: .destructive, action: onRemove) {
                Label("Remove from Recent", systemSymbol: .trash)
            }
        }
    }

    private var recentItemIcon: some View {
        Image(systemSymbol: recentItemSymbol(for: item))
            .foregroundStyle(.secondary)
            .frame(width: 16)
    }
}

public struct EditBoardLinkPanel: View {
    public init() {}

    @Environment(BoardEditingModel.self) private var editing
    @Environment(DenWindowModel.self) private var windowModel

    @State private var text = ""
    @FocusState private var isFocused: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .link) {
                TextField(
                    text: $text,
                    prompt: Text(verbatim: "https://example.com or search")
                ) {
                    Text("Open URL or search")
                }
                .denPanelHeaderField()
                .focused($isFocused)
                .onSubmit { TextInputComposition.performUnlessActive(submit) }
                .onChange(of: text) { _, newValue in
                    let stripped = WebURLPolicy.stripNewlines(newValue)
                    if newValue != stripped {
                        text = stripped
                    }
                    if isFocused {
                        TextInputComposition.syncActiveFieldEditor(to: stripped)
                    }
                }
            }

            DenPanelHint("Replace the Current Sheet in the focused Board")
        }
        .denPanel()
        .onAppear {
            text = editing.focusedBoard?.currentSheetURL?.absoluteString ?? ""
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand {
            windowModel.hideEditBoardLinkPanel()
            editing.restoreFocusedFirstResponder()
        }
    }

    private func submit() {
        if editing.navigateFocusedBoard(urlString: text) {
            text = ""
        }
    }
}

public struct ZmxDuplicationPanel: View {
    public init() {}

    @Environment(BoardEditingModel.self) private var editing
    @Environment(DenWindowModel.self) private var windowModel
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var rootSessionName: String {
        windowModel.zmxDuplicationRootSessionName
            ?? editing.focusedBoard?.zmxSessionName
            ?? "zmx"
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { text },
            set: { text = BoardEditingModel.normalizedZmxSuffix($0) }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .plusSquareOnSquare) {
                TextField(
                    text: textBinding,
                    prompt: Text("Optional suffix, e.g. vi")
                ) {
                    Text("Duplicate zmx Board")
                }
                .denPanelHeaderField()
                .focused($isFocused)
                .accessibilityIdentifier("zmx-duplication-input")
                .onSubmit { TextInputComposition.performUnlessActive(submit) }
            }

            Text("Creates \(rootSessionName)-… in the same Working Directory")
                .foregroundStyle(.secondary)

            HStack(spacing: DenPanelLayout.contentSpacing) {
                DenPanelHint("Letters, numbers, -, _, . only")
                Spacer()
                DenPanelHint("Enter to duplicate · Escape to cancel")
            }
        }
        .denPanel()
        .onAppear {
            text = ""
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand {
            windowModel.hideZmxDuplicationPanel()
            text = ""
            editing.restoreFocusedFirstResponder()
        }
    }

    private func submit() {
        editing.duplicateFocusedZmxBoard(suffix: text)
        text = ""
        editing.restoreFocusedFirstResponder()
    }
}

public struct RenameBoardPanel: View {
    public init() {}

    @Environment(BoardEditingModel.self) private var editing
    @Environment(DenWindowModel.self) private var windowModel
    @State private var text = ""
    @FocusState private var isFocused: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .pencil) {
                TextField(
                    text: $text,
                    prompt: Text("Board label, or leave empty")
                ) {
                    Text("Rename board")
                }
                .denPanelHeaderField()
                .focused($isFocused)
                .onSubmit {
                    TextInputComposition.performUnlessActive {
                        editing.renameFocusedBoard(to: text)
                    }
                }
            }
            DenPanelHint("Leave empty to restore page-provided title")
        }
        .denPanel()
        .onAppear {
            if let board = editing.focusedBoard { text = board.customLabel ?? board.label } else { text = "" }
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand { windowModel.hideRenameBoardPanel() }
    }
}

public struct BoardWidthPanel: View {
    public init() {}

    @Environment(DenWindowModel.self) private var windowModel

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(icon: Image(systemSymbol: .arrowLeftAndRight)) {
                Text("Resize Boards to Fit").font(.headline)
                Spacer()
                DenCloseButton(label: "Close Board Width", action: windowModel.hideBoardWidthPanel)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(1...9, id: \.self) { count in
                    let width = windowModel.boardWidth(toFit: count)
                    Button {
                        windowModel.resizeFocusedDeskBoards(toFit: count)
                    } label: {
                        VStack(spacing: 2) {
                            Text(count == 1 ? "1 Board" : "\(count) Boards")
                            Text(width.map { "\(Int($0.rounded())) pt" } ?? "Unavailable")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(!windowModel.canResizeFocusedDeskBoards(toFit: count))
                    .accessibilityHint("Applies to every Primary Board in the Focused Desk")
                }
            }
            if let message = windowModel.boardWidthPanelMessage {
                DenValidationMessage(message)
            } else {
                DenPanelHint("Changes every Primary Board in the Focused Desk. Press - / = or 1–9, then Escape.")
            }
        }
        .denPanel()
        .onExitCommand { windowModel.hideBoardWidthPanel() }
    }
}

public struct SaveEssentialPanel: View {
    public init() {}

    @Environment(BoardEditingModel.self) private var editing
    @Environment(DenWindowModel.self) private var windowModel

    @State private var name = ""
    @State private var key = ""
    @State private var input = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, key, input
    }

    private var conflictingEssential: Essential? {
        let trimmedKey = key == " " ? key : key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return nil }
        return editing.essentials.first { $0.key == trimmedKey }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .sparkles) {
                Text("Save as Essential")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: DenPanelLayout.controlSpacing) {
                TextField("Name", text: $name, prompt: Text("e.g. ChatGPT"))
                    .focused($focusedField, equals: .name)
                    .onSubmit { focusedField = .key }

                HStack(spacing: DenPanelLayout.controlSpacing) {
                    TextField("Key", text: $key, prompt: Text("e.g. c or C"))
                        .focused($focusedField, equals: .key)
                        .frame(width: 90)
                        .onChange(of: key) { _, value in
                            if value.count > 1 {
                                key = String(value.prefix(1))
                            }
                            errorMessage = nil
                        }
                        .onSubmit {
                            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                focusedField = .input
                            } else {
                                save()
                            }
                        }

                    if let conflict = conflictingEssential {
                        Text("Assigned to '\(conflict.name)' · Saving asks to replace")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if !editing.essentials.isEmpty {
                        Text("Existing keys: \(usedKeysString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                TextField(
                    "Input",
                    text: $input,
                    prompt: Text("URL, search, :terminal, :zellij, or :zmx")
                )
                .focused($focusedField, equals: .input)
                .onSubmit { save() }
            }

            if let errorMessage {
                DenValidationMessage(errorMessage)
            }

            HStack {
                DenPanelHint("Press Return to save, Escape to cancel")
                Spacer()
                Button("Save Essential", action: save)
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
            }
        }
        .denPanel()
        .onAppear {
            if let draft = windowModel.saveEssentialDraft {
                name = draft.name
                key = draft.key
                input = draft.input
            }
            DispatchQueue.main.async {
                if name.isEmpty {
                    focusedField = .name
                } else if key.isEmpty {
                    focusedField = .key
                } else {
                    focusedField = .input
                }
            }
        }
        .onExitCommand { windowModel.hideSaveEssentialPanel() }
    }

    private var usedKeysString: String {
        editing.essentials.map(\.displayKey).joined(separator: ", ")
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = key == " " ? key : key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && trimmedKey.count == 1 && !trimmedInput.isEmpty
    }

    private func save() {
        TextInputComposition.performUnlessActive {
            guard canSave else {
                errorMessage = "Enter a name, one key, and an input."
                return
            }
            if !windowModel.saveEssential(name: name, key: key, input: input) {
                errorMessage = "Could not save Essential."
            }
        }
    }
}
