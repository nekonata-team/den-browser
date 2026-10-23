import AppKit
import DenDomain
import DenModels
import SFSafeSymbols
import SwiftUI

public struct UnactivatedBoardView: View {
    @Environment(DenWindowModel.self) private var windowModel
    let board: BoardState
    let isFocused: Bool
    let isDragging: Bool
    let profileColor: Color
    let width: Double
    let height: Double
    let isPointerFocusEnabled: Bool
    let onFocus: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    public init(
        board: BoardState, isFocused: Bool, isDragging: Bool, profileColor: Color, width: Double, height: Double,
        isPointerFocusEnabled: Bool, onFocus: @escaping () -> Void, onRemove: @escaping () -> Void,
        onDragChanged: @escaping (DragGesture.Value) -> Void, onDragEnded: @escaping (DragGesture.Value) -> Void
    ) {
        self.board = board
        self.isFocused = isFocused
        self.isDragging = isDragging
        self.profileColor = profileColor
        self.width = width
        self.height = height
        self.isPointerFocusEnabled = isPointerFocusEnabled
        self.onFocus = onFocus
        self.onRemove = onRemove
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Color.clear
        }
        .frame(width: width, height: height)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
                .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
        }
        .shadow(
            color: DenSurfaceColors.boardShadow(isFocused: isFocused, isDragging: isDragging),
            radius: isDragging ? 42 : (isFocused ? 34 : 24), x: 0, y: isDragging ? 28 : 22
        )
    }

    private var header: some View {
        HStack(spacing: DenLayout.outerInset) {
            dragHandle
            Button(action: onRemove) {
                Image(systemSymbol: .xmark)
                    .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .help("Remove Board")
            .accessibilityLabel("Remove Board")
        }
        .padding(.horizontal, DenLayout.chromeHorizontalPadding)
        .frame(height: DenLayout.boardHeaderHeight)
        .background(
            windowModel.isDenMode && isFocused
                ? profileColor.opacity(DenSurfaceColors.focusedBoardHeaderOpacity) : Color.clear
        )
        .background(.regularMaterial)
        .modifier(
            BoardHeaderCenteringModifier(
                boardID: board.id,
                isEnabled: isPointerFocusEnabled
            )
        )
    }

    private var dragHandle: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: boardSymbol(for: board.kind))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            BoardHeaderTitle(
                board: board,
                isFocused: isFocused,
                isAnchor: windowModel.focusedDesk?.anchorBoardID == board.id
            )
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if isPointerFocusEnabled { onFocus() } }
        .gesture(
            DragGesture(coordinateSpace: .named(BoardStripCoordinateSpace.name))
                .onChanged { if isPointerFocusEnabled { onDragChanged($0) } }
                .onEnded { if isPointerFocusEnabled { onDragEnded($0) } }
        )
    }

    private var borderColor: Color {
        DenSurfaceColors.boardBorder(isFocused: isFocused, profileColor: profileColor)
    }
}
