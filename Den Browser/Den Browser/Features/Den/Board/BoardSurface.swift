import SwiftUI

struct BoardSurfaceModifier: ViewModifier {
    let boardID: UUID
    let isFocused: Bool
    let isDragging: Bool
    let profileColor: Color
    let width: Double
    let height: Double
    let isFocusModeDeemphasized: Bool
    let isFocusModeFocused: Bool
    let differentiateWithoutColor: Bool
    let shouldReduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: height)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("board-surface.\(boardID.uuidString.lowercased())")
            .clipShape(RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
                    .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
            }
            .shadow(
                color: .black.opacity(isDragging ? 0.55 : (isFocused ? 0.42 : 0.30)),
                radius: isDragging ? 42 : (isFocused ? 34 : 24), x: 0, y: isDragging ? 28 : 22
            )
            .shadow(
                color: isFocusModeFocused ? profileColor.opacity(0.24) : .clear,
                radius: isFocusModeFocused ? DenLayout.focusModeHaloRadius : 0,
                x: 0,
                y: 0
            )
            .scaleEffect(isDragging && !shouldReduceMotion ? 1.02 : 1)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: isFocused)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: isDragging)
            .animation(
                DenMotion.feedback(reduceMotion: shouldReduceMotion),
                value: isFocusModeDeemphasized
            )
            .animation(
                DenMotion.feedback(reduceMotion: shouldReduceMotion),
                value: isFocusModeFocused
            )
    }

    private var borderColor: Color {
        if isFocused {
            return differentiateWithoutColor ? .primary : profileColor.opacity(0.75)
        }
        return Color.primary.opacity(0.16)
    }
}

struct BoardDragHeader<LeadingContent: View>: View {
    let board: BoardState
    let isFocused: Bool
    let isDragging: Bool
    let isPointerFocusEnabled: Bool
    let onFocus: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void
    private let leadingContent: LeadingContent

    init(
        board: BoardState,
        isFocused: Bool,
        isDragging: Bool,
        isPointerFocusEnabled: Bool,
        onFocus: @escaping () -> Void,
        onDragChanged: @escaping (DragGesture.Value) -> Void,
        onDragEnded: @escaping (DragGesture.Value) -> Void,
        onMoveLeft: @escaping () -> Void,
        onMoveRight: @escaping () -> Void,
        @ViewBuilder leadingContent: () -> LeadingContent
    ) {
        self.board = board
        self.isFocused = isFocused
        self.isDragging = isDragging
        self.isPointerFocusEnabled = isPointerFocusEnabled
        self.onFocus = onFocus
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onMoveLeft = onMoveLeft
        self.onMoveRight = onMoveRight
        self.leadingContent = leadingContent()
    }

    var body: some View {
        HStack(spacing: 8) {
            leadingContent
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            BoardHeaderTitle(board: board, isFocused: isFocused)

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
        .accessibilityHint(
            "Drag to reorder this Board within the Focused Desk, or use Board movement actions"
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("board-header.\(board.id.uuidString.lowercased())")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityAction(named: "Move Board Left", onMoveLeft)
        .accessibilityAction(named: "Move Board Right", onMoveRight)
    }
}
