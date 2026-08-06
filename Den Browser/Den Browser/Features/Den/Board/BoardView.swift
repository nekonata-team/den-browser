import SwiftUI
import WebKit

struct BoardView: View {
    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let board: BoardState
    let isFocused: Bool
    let isDragging: Bool
    @ObservedObject var runtime: BoardRuntime
    let profileColor: Color
    let width: Double
    let height: Double
    let isPointerFocusEnabled: Bool
    let onFocus: () -> Void
    let onGoToFirst: () -> Void
    let onGoBack: () -> Void
    let onGoForward: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                BoardWebView(
                    webView: runtime.webView,
                    isFocused: isFocused && !store.isDenMode && store.temporaryContext == nil,
                    isHidden: store.isDrawerOpen,
                    isPointerFocusEnabled: isPointerFocusEnabled,
                    onFocus: onFocus
                )

                if runtime.isLoading {
                    loadingIndicator
                }
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-surface.\(board.id.uuidString.lowercased())")
        .clipShape(RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
                .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
        }
        .shadow(
            color: .black.opacity(isDragging ? 0.55 : (isFocused ? 0.42 : 0.30)),
            radius: isDragging ? 42 : (isFocused ? 34 : 24), x: 0, y: isDragging ? 28 : 22
        )
        .scaleEffect(isDragging && !shouldReduceMotion ? 1.02 : 1)
        .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: isFocused)
        .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: isDragging)
        .onAppear {
            store.sheetNavigation.refreshConfiguration(for: runtime.webView)
        }
    }

    private var loadingIndicator: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(profileColor)
                .frame(
                    width: geometry.size.width * max(0.05, min(runtime.estimatedProgress, 1)),
                    height: 2
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .accessibilityElement()
        .accessibilityLabel("Loading Current Sheet")
        .accessibilityValue("\(Int(runtime.estimatedProgress * 100)) percent")
    }

    private var borderColor: Color {
        if isFocused {
            return profileColor.opacity(0.75)
        }
        return Color.primary.opacity(0.16)
    }

    private var header: some View {
        headerContent
            .contextMenu {
                if isContextMenuEnabled {
                    boardContextMenu
                }
            }
    }

    private var headerContent: some View {
        HStack(spacing: DenLayout.outerInset) {
            dragHandle

            navigationButtons
        }
        .padding(.horizontal, DenLayout.chromeHorizontalPadding)
        .frame(height: DenLayout.boardHeaderHeight)
        .background(store.isDenMode && isFocused ? profileColor.opacity(0.12) : Color.clear)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var boardContextMenu: some View {
        Button {
            store.focusBoard(board.id)
            store.duplicateFocusedBoard()
        } label: {
            Label("Duplicate Current Sheet", systemImage: "plus.square.on.square")
        }
        .onAppear {
            store.focusBoard(board.id)
        }

        Button {
            store.focusBoard(board.id)
            store.keepFocusedSheetInDrawer()
        } label: {
            Label("Keep Current Sheet in Drawer", systemImage: "tray.and.arrow.down")
        }

        Button {
            runtime.webView.reload()
        } label: {
            Label("Reload Current Sheet", systemImage: "arrow.clockwise")
        }

        Button {
            store.focusBoard(board.id)
            store.goToFirstSheetInFocusedBoard()
        } label: {
            Label("Return to First Sheet", systemImage: "backward.end")
        }
        .disabled(!canReturnToFirstSheet)

        if store.sheetNavigation.isEnabled {
            Button {
                store.sheetNavigation.setBoardPaused(
                    !store.sheetNavigation.isBoardPaused(board.id),
                    for: board.id
                )
            } label: {
                Label(
                    store.sheetNavigation.isBoardPaused(board.id)
                        ? "Resume Sheet Navigation for this Board"
                        : "Pause Sheet Navigation for this Board",
                    systemImage: store.sheetNavigation.isBoardPaused(board.id) ? "play.circle" : "pause.circle"
                )
            }
        }

        Button {
            store.focusBoard(board.id)
            store.captureFocusedSheetScreenshot()
        } label: {
            Label("Capture Current Sheet Screenshot...", systemImage: "camera")
        }

        if preferences.nativePictureInPictureEnabled {
            Button {
                runtime.togglePictureInPicture()
            } label: {
                Label("Toggle Picture in Picture", systemImage: "pip")
            }
        }

        Divider()

        Button {
            store.focusBoard(board.id)
            store.toggleFocusedBoardMaximized()
        } label: {
            Label(maximizationLabel, systemImage: maximizationSystemImage)
        }

        Button {
            store.focusBoard(board.id)
            store.centerFocusedBoard()
        } label: {
            Label("Center Board", systemImage: "scope")
        }

        Divider()

        Button {
            store.focusBoard(board.id)
            store.moveFocusedBoardLeft()
        } label: {
            Label("Move Board Left", systemImage: "arrow.left")
        }
        .disabled(!store.canMoveBoard(board.id, by: -1))

        Button {
            store.focusBoard(board.id)
            store.moveFocusedBoardRight()
        } label: {
            Label("Move Board Right", systemImage: "arrow.right")
        }
        .disabled(!store.canMoveBoard(board.id, by: 1))

        if store.state.desks.count > 1 {
            Menu {
                ForEach(Array(store.state.desks.enumerated()), id: \.element.id) { entry in
                    if entry.element.id != boardDeskID {
                        Button("\(entry.offset + 1). \(entry.element.label)") {
                            store.focusBoard(board.id)
                            store.moveFocusedBoard(toDeskNumber: entry.offset + 1)
                        }
                    }
                }
            } label: {
                Label("Move to Desk", systemImage: "rectangle.stack")
            }
        }

        Divider()

        Button(role: .destructive) {
            store.removeBoard(board.id)
        } label: {
            Label("Remove Board", systemImage: "xmark")
        }
    }

    private var dragHandle: some View {
        HStack(spacing: 8) {
            AsyncImage(url: runtime.faviconURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)

            Text(board.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityLabel("Board: \(board.displayName), \(accessibilityState)")

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isPointerFocusEnabled else { return }
            onFocus()
        }
        .gesture(
            DragGesture(coordinateSpace: .named(BoardStripCoordinateSpace.name))
                .onChanged { value in
                    guard isPointerFocusEnabled else { return }
                    onDragChanged(value)
                }
                .onEnded { value in
                    guard isPointerFocusEnabled else { return }
                    onDragEnded(value)
                }
        )
        .pointerStyle(isDragging ? .grabActive : .grabIdle)
        .help("Drag to move Board")
        .accessibilityHint("Drag to reorder this Board within the Focused Desk")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("board-header.\(board.id.uuidString.lowercased())")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            if store.sheetNavigation.isEnabled {
                Button {
                    store.sheetNavigation.setBoardPaused(
                        !store.sheetNavigation.isBoardPaused(board.id),
                        for: board.id
                    )
                } label: {
                    Image(
                        systemName: store.sheetNavigation.isBoardPaused(board.id)
                            ? "pause.circle.fill" : "keyboard"
                    )
                    .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .help(
                    store.sheetNavigation.isBoardPaused(board.id)
                        ? "Resume Sheet Navigation for this Board" : "Pause Sheet Navigation for this Board"
                )
                .accessibilityLabel(
                    store.sheetNavigation.isBoardPaused(board.id)
                        ? "Resume Sheet Navigation for this Board" : "Pause Sheet Navigation for this Board")
            }

            withBoardContextMenu(
                Button(action: onGoToFirst) {
                    Image(systemName: "backward.end")
                        .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(
                    canReturnToFirstSheet
                        ? Color.primary
                        : Color.secondary.opacity(0.35)
                )
                .disabled(!canReturnToFirstSheet)
                .help("Return to First Sheet")
                .accessibilityLabel("Return to First Sheet")
            )

            withBoardContextMenu(
                Button(action: onGoBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(
                    runtime.webView.canGoBack
                        ? Color.primary
                        : Color.secondary.opacity(0.35)
                )
                .disabled(!runtime.webView.canGoBack)
                .help("Back in sheet stack")
                .accessibilityLabel("Back in sheet stack")
            )

            withBoardContextMenu(
                Button(action: onGoForward) {
                    Image(systemName: "chevron.right")
                        .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(
                    runtime.webView.canGoForward
                        ? Color.primary
                        : Color.secondary.opacity(0.35)
                )
                .disabled(!runtime.webView.canGoForward)
                .help("Forward in sheet stack")
                .accessibilityLabel("Forward in sheet stack")
            )

            withBoardContextMenu(
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .padding(.leading, 4)
                .help("Remove Board")
                .accessibilityLabel("Remove Board")
            )
        }
    }

    private func withBoardContextMenu<Content: View>(_ content: Content) -> some View {
        content.contextMenu {
            if isContextMenuEnabled {
                boardContextMenu
            }
        }
    }

    private var accessibilityState: String {
        if isFocused {
            return "Focused board"
        }
        return "Board"
    }

    private var canReturnToFirstSheet: Bool {
        guard
            let firstSheetURL = board.firstSheetURL,
            let currentSheetURL = board.currentSheetURL
        else { return false }
        return currentSheetURL != firstSheetURL
    }

    private var isContextMenuEnabled: Bool {
        isPointerFocusEnabled && !store.isBoardDragging
    }

    private var boardDeskID: UUID? {
        store.boardIndices(for: board.id).map { store.state.desks[$0.desk].id }
    }

    private var maximizationLabel: String {
        store.maximizedBoardID == board.id ? "Restore Board Size" : "Maximize Board"
    }

    private var maximizationSystemImage: String {
        store.maximizedBoardID == board.id
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}

enum BoardStripCoordinateSpace {
    static let name = "board-strip"
}
