import DenDesign
import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

struct BoardFocusRequest: Equatable {
    let deskID: DeskID
    let boardID: BoardID
}

struct BoardHeaderTitle: View {
    let board: BoardState
    let isFocused: Bool
    var isAnchor: Bool = false

    var body: some View {
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

struct BoardSurfaceModifier: ViewModifier {
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

    func body(content: Content) -> some View {
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

struct BoardHeaderCenteringModifier: ViewModifier {
    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel

    let boardID: BoardID
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    guard isEnabled else { return }
                    controller.focusBoard(boardID, exitsDenMode: true)
                    windowModel.centerFocusedBoard()
                }
        )
    }
}

struct BoardDragHeader<LeadingContent: View>: View {
    @Environment(DenController.self) private var controller
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

            BoardHeaderTitle(
                board: board,
                isFocused: isFocused,
                isAnchor: controller.focusedDesk?.anchorBoardID == board.id
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

extension DenMotion {
    static func boardTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }
}

struct BoardInputSourceBadge: View {
    let label: String
    let isFocused: Bool

    var body: some View {
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
