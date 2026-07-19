import AppKit
import SwiftUI
import WebKit

struct BoardView: View {
    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var isDragHandleHovered = false

    let board: BoardState
    let isFocused: Bool
    let isDragging: Bool
    let runtime: BoardRuntime
    let width: Double
    let height: Double
    let isPointerFocusEnabled: Bool
    let onFocus: () -> Void
    let onGoBack: () -> Void
    let onGoForward: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            BoardWebView(
                webView: runtime.webView,
                isFocused: isFocused && !store.isDenMode,
                isPointerFocusEnabled: isPointerFocusEnabled,
                onFocus: onFocus
            )
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
        }
        .shadow(
            color: .black.opacity(isDragging ? 0.55 : (isFocused ? 0.42 : 0.30)),
            radius: isDragging ? 42 : (isFocused ? 34 : 24), x: 0, y: isDragging ? 28 : 22
        )
        .scaleEffect(isDragging && !shouldReduceMotion ? 1.02 : 1)
        .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: isFocused)
        .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: isDragging)
    }

    private var borderColor: Color {
        if isFocused {
            return .cyan.opacity(0.75)
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
        HStack(spacing: 8) {
            dragHandle

            navigationButtons
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            if store.isDenMode, isFocused {
                Rectangle()
                    .fill(.cyan.opacity(0.9))
                    .frame(height: 3)
            }
        }
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
            runtime.webView.reload()
        } label: {
            Label("Reload Current Sheet", systemImage: "arrow.clockwise")
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
            Text(board.displayName)
                .font(.system(size: 12, weight: .semibold))
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
        .onHover { isHovering in
            isDragHandleHovered = isHovering
            (isHovering ? (isDragging ? NSCursor.closedHand : NSCursor.openHand) : NSCursor.arrow).set()
        }
        .onChange(of: isDragging) { _, isDragging in
            guard isDragHandleHovered else { return }
            (isDragging ? NSCursor.closedHand : NSCursor.openHand).set()
        }
        .help("Drag to move Board")
        .accessibilityHint("Drag to reorder this Board within the Focused Desk")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("board-header.\(board.id.uuidString.lowercased())")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            withBoardContextMenu(
                Button(action: onGoBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .disabled(!runtime.webView.canGoBack)
                .help("Back in sheet stack")
                .accessibilityLabel("Back in sheet stack")
            )

            withBoardContextMenu(
                Button(action: onGoForward) {
                    Image(systemName: "chevron.right")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .disabled(!runtime.webView.canGoForward)
                .help("Forward in sheet stack")
                .accessibilityLabel("Forward in sheet stack")
            )

            withBoardContextMenu(
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
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
