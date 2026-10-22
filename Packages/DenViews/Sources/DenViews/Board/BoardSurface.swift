import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

public struct BoardHeaderTitle: View {
    let board: BoardState
    let isFocused: Bool
    var isAnchor: Bool = false

    public init(board: BoardState, isFocused: Bool, isAnchor: Bool = false) {
        self.board = board
        self.isFocused = isFocused
        self.isAnchor = isAnchor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(board.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if board.isSideBoard {
                    Image(systemSymbol: .sidebarRight)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Side Board")
                }

                if isAnchor {
                    Image(systemSymbol: .pinFill)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Anchor Board")
                }
            }

            if let supplementaryText {
                Text(supplementaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(supplementaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var supplementaryText: String? {
        if let currentSheetURL = board.currentSheetURL {
            return currentSheetURL.absoluteString
        }
        return board.zellijSessionName ?? board.zmxSessionName
    }

    private var accessibilityLabel: String {
        [
            board.isSideBoard ? "Side board" : nil,
            isAnchor ? "Anchor board" : nil,
            "Board: \(board.displayName)",
            supplementaryText,
            isFocused ? "Focused board" : "Board",
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

public struct BoardSurfaceModifier: ViewModifier {
    let boardID: BoardID
    let isFocused: Bool
    let isDragging: Bool
    let profileColor: Color
    let width: Double
    let height: Double
    let isFocusModeDeemphasized: Bool
    let isFocusModeFocused: Bool
    let differentiateWithoutColor: Bool
    let shouldReduceMotion: Bool

    public init(
        boardID: BoardID, isFocused: Bool, isDragging: Bool, profileColor: Color, width: Double, height: Double,
        isFocusModeDeemphasized: Bool, isFocusModeFocused: Bool, differentiateWithoutColor: Bool,
        shouldReduceMotion: Bool
    ) {
        self.boardID = boardID
        self.isFocused = isFocused
        self.isDragging = isDragging
        self.profileColor = profileColor
        self.width = width
        self.height = height
        self.isFocusModeDeemphasized = isFocusModeDeemphasized
        self.isFocusModeFocused = isFocusModeFocused
        self.differentiateWithoutColor = differentiateWithoutColor
        self.shouldReduceMotion = shouldReduceMotion
    }

    public func body(content: Content) -> some View {
        content
            .frame(width: width, height: height)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("board-surface.\(boardID.rawValue.uuidString.lowercased())")
            .clipShape(RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
                    .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
            }
            .shadow(
                color: DenSurfaceColors.boardShadow(isFocused: isFocused, isDragging: isDragging),
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
        if isFocused && differentiateWithoutColor {
            return .primary
        }
        return DenSurfaceColors.boardBorder(isFocused: isFocused, profileColor: profileColor)
    }
}

private struct BoardHeaderDoubleClickHandlerKey: EnvironmentKey {
    public static let defaultValue: ((BoardID) -> Void)? = nil
}

public extension EnvironmentValues {
    var boardHeaderDoubleClickHandler: ((BoardID) -> Void)? {
        get { self[BoardHeaderDoubleClickHandlerKey.self] }
        set { self[BoardHeaderDoubleClickHandlerKey.self] = newValue }
    }
}

public struct BoardHeaderCenteringModifier: ViewModifier {
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(\.boardHeaderDoubleClickHandler) private var onHeaderDoubleClick

    let boardID: BoardID
    let isEnabled: Bool

    public init(boardID: BoardID, isEnabled: Bool) {
        self.boardID = boardID
        self.isEnabled = isEnabled
    }

    public func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    guard isEnabled else { return }
                    if let onHeaderDoubleClick {
                        onHeaderDoubleClick(boardID)
                    } else {
                        windowModel.focusBoard(boardID, exitsDenMode: true)
                        windowModel.centerFocusedBoard()
                    }
                }
        )
    }
}

public struct BoardDragHeader<LeadingContent: View>: View {
    @Environment(DenWindowModel.self) private var windowModel
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

    public init(
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

    public var body: some View {
        HStack(spacing: 8) {
            leadingContent
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            BoardHeaderTitle(
                board: board,
                isFocused: isFocused,
                isAnchor: windowModel.focusedDesk?.anchorBoardID == board.id
            )

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
        .help("Drag to move this Board Group")
        .accessibilityHint(
            "Drag to reorder this Board Group within the Focused Desk, or use Board movement actions"
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("board-header.\(board.id.rawValue.uuidString.lowercased())")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityAction(named: "Move Board Left", onMoveLeft)
        .accessibilityAction(named: "Move Board Right", onMoveRight)
    }
}

public extension DenMotion {
    static func boardTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }
}

public struct BoardInputSourceBadge: View {
    let label: String
    let isFocused: Bool

    public init(label: String, isFocused: Bool) {
        self.label = label
        self.isFocused = isFocused
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundStyle(isFocused ? Color.primary : Color.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
                    .fill(isFocused ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
                    .stroke(isFocused ? Color.primary.opacity(0.2) : Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
            .accessibilityLabel("Input method: \(label)")
    }
}

public enum BoardStripCoordinateSpace {
    public static let name = "board-strip"
}
