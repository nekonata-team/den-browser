import SwiftUI

struct OpenBoardPanel: View {
    private static let maximumVisibleRecentItemCount = 5

    @Environment(DenStore.self) private var store
    @FocusState private var isFocused: Bool
    @State private var selectedRecentItemID: RecentItem?

    let newBoardWidth: Double

    private var filteredRecentItems: [RecentItem] {
        let query = store.openBoardPanelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(
            store.recentItems.lazy.filter {
                query.isEmpty || $0.displayText.localizedCaseInsensitiveContains(query)
            }.prefix(Self.maximumVisibleRecentItemCount))
    }

    private var urlTextBinding: Binding<String> {
        Binding(
            get: { store.openBoardPanelInput },
            set: { store.openBoardPanelInput = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemImage: "plus.rectangle.on.rectangle") {
                TextField(
                    text: urlTextBinding,
                    prompt: Text("https://example.com, search, or :terminal / :zellij / :zmx")
                ) {
                    Text("Open URL, search, or command")
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
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
                    store.openBoardPanelInput = selected.displayText
                    return .handled
                }
                .onSubmit {
                    TextInputComposition.performUnlessActive {
                        if let selected = filteredRecentItems.first(where: { $0.id == selectedRecentItemID }) {
                            openRecent(selected)
                        } else {
                            openBoard()
                        }
                    }
                }
            }

            if let message = store.openBoardPanelMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !filteredRecentItems.isEmpty {
                HStack {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", action: store.clearRecent)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear Recent")
                }

                ForEach(filteredRecentItems) { item in
                    let matchedEssential = store.essentials.first { item.matches(essential: $0) }
                    HStack(spacing: DenPanelLayout.controlSpacing) {
                        Button {
                            openRecent(item)
                        } label: {
                            HStack(spacing: DenPanelLayout.controlSpacing) {
                                Image(systemName: item.systemImage)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(item.displayText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens a new Board")

                        if let matchedEssential {
                            HStack(spacing: 4) {
                                ShortcutChip(tokens: [matchedEssential.displayKey])
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                            }
                            .help("Essential: \(matchedEssential.name) [\(matchedEssential.displayKey)]")
                            .accessibilityLabel(
                                "Essential: \(matchedEssential.name), key \(matchedEssential.displayKey)")
                        } else {
                            Button {
                                store.showSaveEssentialPanel(for: item)
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Save as Essential…")
                            .accessibilityLabel("Save as Essential…")
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
                    .background(
                        item.id == selectedRecentItemID ? Color.primary.opacity(0.1) : Color.clear,
                        in: RoundedRectangle(
                            cornerRadius: DenRadius.small,
                            style: .continuous)
                    )
                    .contextMenu {
                        if let matchedEssential {
                            Button {
                            } label: {
                                Label("Saved as Essential [\(matchedEssential.displayKey)]", systemImage: "sparkles")
                            }
                            .disabled(true)
                        } else {
                            Button {
                                store.showSaveEssentialPanel(for: item)
                            } label: {
                                Label("Save as Essential…", systemImage: "sparkles")
                            }
                        }
                    }
                }
            }

            HStack(spacing: DenPanelLayout.contentSpacing) {
                Text("Use :terminal [path], :zellij [session], or :zmx [session] for a Terminal Board")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("n in Den Mode")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .denPanel()
        .onAppear {
            if let initialURL = store.openBoardPanelInitialURL {
                store.openBoardPanelInput = initialURL.absoluteString
            }
            DispatchQueue.main.async { isFocused = true }
        }
        .onChange(of: store.openBoardPanelInput) { _, _ in
            selectedRecentItemID = nil
            store.openBoardPanelMessage = nil
        }
        .onExitCommand {
            store.hideOpenBoardPanel()
            store.restoreFocusedFirstResponder()
        }
    }

    private func openBoard() {
        store.openBoard(
            input: store.openBoardPanelInput,
            preferredWidth: newBoardWidth,
            afterBoardID: store.openBoardAfterBoardID)
        finishOpeningBoardIfNeeded()
    }

    private func openRecent(_ item: RecentItem) {
        store.openBoard(
            recentItem: item,
            preferredWidth: newBoardWidth,
            afterBoardID: store.openBoardAfterBoardID)
        finishOpeningBoardIfNeeded()
    }

    private func finishOpeningBoardIfNeeded() {
        guard !store.isOpenBoardPanelPresented else { return }
        store.clearOpenBoardPanelDraft()
    }

    private func moveRecentSelection(by offset: Int) {
        guard !filteredRecentItems.isEmpty else { return }
        let ids = filteredRecentItems.map(\.id)
        guard let selectedRecentItemID, let index = ids.firstIndex(of: selectedRecentItemID) else {
            self.selectedRecentItemID = offset > 0 ? ids.first : ids.last
            return
        }
        self.selectedRecentItemID = ids[(index + offset + ids.count) % ids.count]
    }
}

struct EditBoardLinkPanel: View {
    @Environment(DenStore.self) private var store

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemImage: "link") {
                TextField(
                    text: $text,
                    prompt: Text("https://example.com or search")
                ) {
                    Text("Open URL or search")
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .focused($isFocused)
                .onSubmit { TextInputComposition.performUnlessActive(submit) }
            }

            HStack(spacing: DenPanelLayout.contentSpacing) {
                Text("Replace the Current Sheet in the focused Board")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘L")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .denPanel()
        .onAppear {
            text = store.focusedBoard?.currentSheetURL?.absoluteString ?? ""
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand {
            store.hideEditBoardLinkPanel()
            store.restoreFocusedFirstResponder()
        }
    }

    private func submit() {
        if store.navigateFocusedBoard(urlString: text) {
            text = ""
        }
    }
}

struct ZmxDuplicationPanel: View {
    @Environment(DenStore.self) private var store
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var rootSessionName: String {
        store.zmxDuplicationRootSessionName
            ?? store.focusedBoard?.zmxSessionName
            ?? "zmx"
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { text },
            set: { text = ZmxSessionNameGenerator.normalizedSuffix($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemImage: "plus.square.on.square") {
                TextField(
                    text: textBinding,
                    prompt: Text("Optional suffix, e.g. vi")
                ) {
                    Text("Duplicate zmx Board")
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .focused($isFocused)
                .accessibilityIdentifier("zmx-duplication-input")
                .onSubmit { TextInputComposition.performUnlessActive(submit) }
            }

            Text("Creates \(rootSessionName)-… in the same Working Directory")
                .foregroundStyle(.secondary)

            HStack(spacing: DenPanelLayout.contentSpacing) {
                Text("Letters, numbers, -, _, . only")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Enter to duplicate · Escape to cancel")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .denPanel()
        .onAppear {
            text = ""
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand {
            store.hideZmxDuplicationPanel()
            text = ""
            store.restoreFocusedFirstResponder()
        }
    }

    private func submit() {
        guard store.duplicateFocusedZmxBoard(suffix: text) else { return }
        text = ""
        store.restoreFocusedFirstResponder()
    }
}

struct RenameBoardPanel: View {
    @Environment(DenStore.self) private var store
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemImage: "pencil") {
                TextField(
                    text: $text,
                    prompt: Text("Board label, or leave empty")
                ) {
                    Text("Rename board")
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .focused($isFocused)
                .onSubmit {
                    TextInputComposition.performUnlessActive {
                        store.renameFocusedBoard(to: text)
                    }
                }
            }
            HStack(spacing: DenPanelLayout.contentSpacing) {
                Text("Leave empty to restore page-provided title").foregroundStyle(.secondary)
                Spacer()
                Text("r in Den Mode").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .denPanel()
        .onAppear {
            if let board = store.focusedBoard { text = board.customLabel ?? board.label } else { text = "" }
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand { store.hideRenameBoardPanel() }
    }
}

struct BoardWidthPanel: View {
    @Environment(DenStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            HStack {
                Text("Resize Boards to Fit").font(.headline)
                Spacer()
                DenCloseButton(label: "Close Board Width", action: store.hideBoardWidthPanel)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(1...9, id: \.self) { count in
                    let width = store.boardWidth(toFit: count)
                    Button {
                        store.resizeFocusedDeskBoards(toFit: count)
                    } label: {
                        VStack(spacing: 2) {
                            Text(count == 1 ? "1 Board" : "\(count) Boards")
                            Text(width.map { "\(Int($0.rounded())) pt" } ?? "Unavailable")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(!store.canResizeFocusedDeskBoards(toFit: count))
                    .accessibilityHint("Applies to every Board in the Focused Desk")
                }
            }
            Text(
                store.boardWidthPanelMessage
                    ?? "Changes every Board in the Focused Desk. Press - / = or 1–9, then Escape."
            )
            .font(.caption)
            .foregroundStyle(store.boardWidthPanelMessage == nil ? Color.secondary : Color.red)
        }
        .denPanel(width: DenPanelLayout.compactWidth)
        .onExitCommand { store.hideBoardWidthPanel() }
    }
}

struct SaveEssentialPanel: View {
    @Environment(DenStore.self) private var store

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
        return store.essentials.first { $0.key == trimmedKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemImage: "sparkles") {
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
                        Text("Already used by '\(conflict.name)'")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else if !store.essentials.isEmpty {
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
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Press Return to save, Escape to cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save Essential", action: save)
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
            }
        }
        .denPanel(width: 380)
        .onAppear {
            if let draft = store.saveEssentialDraft {
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
        .onExitCommand { store.hideSaveEssentialPanel() }
    }

    private var usedKeysString: String {
        store.essentials.map(\.displayKey).joined(separator: ", ")
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = key == " " ? key : key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && trimmedKey.count == 1 && !trimmedInput.isEmpty && conflictingEssential == nil
    }

    private func save() {
        TextInputComposition.performUnlessActive {
            guard canSave else {
                if let conflict = conflictingEssential {
                    errorMessage = "Key '\(conflict.displayKey)' is already used by '\(conflict.name)'."
                } else {
                    errorMessage = "Enter a name, one key, and an input."
                }
                return
            }
            if !store.saveEssential(name: name, key: key, input: input) {
                errorMessage = "Could not save Essential."
            }
        }
    }
}
