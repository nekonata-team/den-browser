import SwiftUI

struct OpenBoardPanel: View {
    private static let maximumVisibleRecentItemCount = 5

    @Binding var urlText: String
    @FocusState.Binding var isFocused: Bool
    @State private var selectedRecentItemID: RecentItem?

    let defaultBoardWidth: Double
    let initialURL: URL?
    let recentItems: [RecentItem]
    let message: String?
    let onSubmit: (Double) -> Void
    let onOpenRecent: (RecentItem, Double) -> Void
    let onClearRecent: () -> Void
    let onDismiss: () -> Void
    let onInputChange: () -> Void

    private var filteredRecentItems: [RecentItem] {
        let query = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(
            recentItems.lazy.filter {
                query.isEmpty || $0.displayText.localizedCaseInsensitiveContains(query)
            }.prefix(Self.maximumVisibleRecentItemCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemImage: "plus.rectangle.on.rectangle") {
                TextField("Open URL, search, or command", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.medium))
                    .focused($isFocused)
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
                    .onSubmit {
                        TextInputComposition.performUnlessActive {
                            if let selected = filteredRecentItems.first(where: { $0.id == selectedRecentItemID }) {
                                onOpenRecent(selected, defaultBoardWidth)
                            } else {
                                onSubmit(defaultBoardWidth)
                            }
                        }
                    }
            }

            if let message {
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
                    Button("Clear", action: onClearRecent)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear Recent")
                }

                ForEach(filteredRecentItems) { item in
                    Button {
                        onOpenRecent(item, defaultBoardWidth)
                    } label: {
                        HStack(spacing: DenPanelLayout.controlSpacing) {
                            Image(systemName: item.systemImage)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(item.displayText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(
                            item.id == selectedRecentItemID ? Color.primary.opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens a new Board")
                }
            }

            HStack(spacing: DenPanelLayout.contentSpacing) {
                Text("Use :terminal [path] for a Terminal Board or :zellij [session] for a Zellij Board")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("n in Den Mode")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .denPanel()
        .onAppear {
            if let initialURL {
                urlText = initialURL.absoluteString
            }
            DispatchQueue.main.async { isFocused = true }
        }
        .onChange(of: urlText) { _, _ in
            selectedRecentItemID = nil
            onInputChange()
        }
        .onExitCommand(perform: onDismiss)
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

    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemImage: "link") {
                TextField("Open URL or search", text: $text)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.medium))
                    .focused($isFocused)
                    .onSubmit { TextInputComposition.performUnlessActive(onSubmit) }
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
        .onExitCommand(perform: onDismiss)
    }
}

struct RenameBoardPanel: View {
    @Environment(DenStore.self) private var store
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemImage: "pencil") {
                TextField("Rename board", text: $text)
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
