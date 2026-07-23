import SwiftUI

struct OpenBoardPanel: View {
    @Binding var urlText: String
    @FocusState.Binding var isFocused: Bool

    let defaultBoardWidth: Double
    let initialURL: URL?
    let onSubmit: (Double) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .foregroundStyle(.secondary)

                TextField("Open URL or search", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isFocused)
                    .onSubmit { onSubmit(defaultBoardWidth) }
            }
            .frame(height: 38)

            HStack(spacing: 12) {
                Text("New board opens to the right of the focused board")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("n in Den Mode")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            if let initialURL {
                urlText = initialURL.absoluteString
            }
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand(perform: onDismiss)
    }
}

struct EditBoardLinkPanel: View {
    @Environment(DenStore.self) private var store

    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)

                TextField("Open URL or search", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isFocused)
                    .onSubmit { onSubmit() }
            }
            .frame(height: 38)

            HStack(spacing: 12) {
                Text("Replace the Current Sheet in the focused Board")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘L")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "pencil").foregroundStyle(.secondary)
                TextField("Rename board", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isFocused)
                    .onSubmit { store.renameFocusedBoard(to: text) }
            }
            .frame(height: 38)
            HStack(spacing: 12) {
                Text("Leave empty to restore page-provided title").foregroundStyle(.secondary)
                Spacer()
                Text("r in Den Mode").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Resize Boards to Fit").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: store.hideBoardWidthPanel) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Close Board Width")
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
                                .font(.system(size: 10)).foregroundStyle(.secondary)
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
            .font(.system(size: 12))
            .foregroundStyle(store.boardWidthPanelMessage == nil ? Color.secondary : Color.red)
        }
        .padding(16)
        .frame(width: 420)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onExitCommand { store.hideBoardWidthPanel() }
    }
}
