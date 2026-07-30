import AppKit
import SwiftUI

struct BoardStrip: View {
    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @Binding var boardDrag: BoardDragState?
    @Binding var resizingBoardID: UUID?
    @Binding var scrollPosition: ScrollPosition

    let size: CGSize
    let shouldShowDeskSwitcher: Bool
    let profileColor: Color
    let boardSpacing: CGFloat
    let boardHorizontalPadding: CGFloat
    let isPointerFocusEnabled: (UUID) -> Bool
    let onDragChanged: (BoardState, DragGesture.Value, CGSize) -> Void
    let onDragEnded: (DragGesture.Value, CGSize) -> Void
    let onFramesChanged: ([UUID: CGRect]) -> Void
    let onOpenBoardAtEnd: (UUID) -> Void
    let onAppear: (Bool, CGFloat) -> Void
    let onAlignmentChanged: (BoardStripAlignmentTarget, BoardStripAlignmentTarget) -> Void
    let onCenterRequest: () -> Void

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    var body: some View {
        let boards =
            store.isDeskFilterPresented
            ? store.filteredDeskBoards
            : store.focusedDesk?.boards ?? []
        let topInset = shouldShowDeskSwitcher ? DenLayout.boardTopInsetWithDeskSwitcher : DenLayout.outerInset
        let bottomInset = DenLayout.outerInset
        let boardHeight = max(DenLayout.minimumBoardHeight, size.height - topInset - bottomInset)
        let maximizedBoardWidth = max(
            CGFloat(BoardState.minimumWidth),
            size.width - boardHorizontalPadding * 2)
        let layoutParams = BoardLayout.Parameters(
            centering: preferences.boardCentering,
            boards: boards,
            maximizedBoardID: store.maximizedBoardID,
            windowWidth: size.width,
            horizontalPadding: boardHorizontalPadding,
            spacing: boardSpacing
        )
        let paddings = BoardLayout.calculatePaddings(for: layoutParams)
        let shouldCenterFocusedBoard = BoardLayout.shouldCenterFocusedBoard(for: layoutParams)
        let restingScrollX = BoardLayout.restingScrollX(for: layoutParams)
        let alignmentTarget = BoardStripAlignmentTarget(
            deskID: store.state.focusedDeskID,
            boardID: store.focusedDesk?.focusedBoardID,
            centersFocusedBoard: shouldCenterFocusedBoard,
            restingScrollX: restingScrollX
        )

        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: boardSpacing) {
                ForEach(boards) { board in
                    BoardView(
                        board: board,
                        isFocused:
                            store.isDeskFilterPresented
                            ? board.id == store.deskFilterSelectionBoardID
                            : board.id == store.focusedDesk?.focusedBoardID,
                        isDragging: boardDrag?.boardID == board.id,
                        runtime: store.runtime(for: board),
                        profileColor: profileColor,
                        width: store.maximizedBoardID == board.id ? maximizedBoardWidth : board.width,
                        height: boardHeight,
                        isPointerFocusEnabled:
                            !store.isDeskFilterPresented && isPointerFocusEnabled(board.id),
                        onFocus: {
                            if store.isDeskFilterPresented {
                                store.confirmDeskFilterSelection(board.id)
                            } else {
                                store.focusBoard(board.id, exitsDenMode: true)
                            }
                        },
                        onGoBack: { store.goBackInBoard(board.id) },
                        onGoForward: { store.goForwardInBoard(board.id) },
                        onRemove: { store.removeBoard(board.id) },
                        onDragChanged: { onDragChanged(board, $0, size) },
                        onDragEnded: { onDragEnded($0, size) }
                    )
                    .disabled(store.isDeskFilterPresented)
                    .overlay {
                        if store.isDeskFilterPresented {
                            Button {
                                store.confirmDeskFilterSelection(board.id)
                            } label: {
                                Color.clear
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Enter \(board.displayName) Board")
                        }
                    }
                    .id(board.id)
                    .transition(DenMotion.boardTransition(reduceMotion: shouldReduceMotion))
                    .offset(
                        x: boardDrag?.boardID == board.id ? boardDrag?.offset.width ?? 0 : 0,
                        y: boardDrag?.boardID == board.id ? boardDrag?.offset.height ?? 0 : 0
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BoardFramePreferenceKey.self,
                                value: [board.id: proxy.frame(in: .named(BoardStripCoordinateSpace.name))]
                            )
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if !store.isDeskFilterPresented && store.maximizedBoardID != board.id {
                            BoardResizeHandle(
                                board: board,
                                height: boardHeight,
                                width: boardSpacing,
                                onResizeStart: {
                                    resizingBoardID = board.id
                                    store.focusBoard(board.id)
                                },
                                onResize: { store.resizeBoard(board.id, to: $0) },
                                onResizeEnd: {
                                    store.saveBoardWidths()
                                    resizingBoardID = nil
                                }
                            )
                            .offset(x: boardSpacing)
                        }
                    }
                    .allowsHitTesting(isPointerFocusEnabled(board.id))
                    .accessibilityHidden(!isPointerFocusEnabled(board.id))
                    .zIndex(boardDrag?.boardID == board.id ? 2 : 1)
                }

                if !store.isDeskFilterPresented, let lastBoardID = boards.last?.id {
                    Button {
                        onOpenBoardAtEnd(lastBoardID)
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .glassEffect(.regular, in: Circle())
                    .frame(height: boardHeight)
                    .help("Open Board at End of Desk")
                    .accessibilityLabel("Open Board at End of Desk")
                }
            }
            .scrollTargetLayout()
            .padding(.leading, paddings.leading)
            .padding(.trailing, paddings.trailing)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: boards.map(\.id))
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: boards.map(\.width))
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.maximizedBoardID)
        }
        .scrollPosition($scrollPosition, anchor: .center)
        .coordinateSpace(name: BoardStripCoordinateSpace.name)
        .scrollIndicators(.never)
        .accessibilityIdentifier("board-strip")
        .onPreferenceChange(BoardFramePreferenceKey.self, perform: onFramesChanged)
        .onAppear {
            onAppear(shouldCenterFocusedBoard, restingScrollX)
        }
        .onChange(of: alignmentTarget) { previous, current in
            onAlignmentChanged(previous, current)
        }
        .onChange(of: store.centerFocusedBoardRequest) { _, _ in
            onCenterRequest()
        }
        .onChange(of: store.deskFilterSelectionBoardID) { _, boardID in
            guard store.isDeskFilterPresented, let boardID else { return }
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                scrollPosition.scrollTo(id: boardID, anchor: .center)
            }
        }
    }
}

struct BoardStripAlignmentTarget: Equatable {
    let deskID: UUID?
    let boardID: UUID?
    let centersFocusedBoard: Bool
    let restingScrollX: CGFloat
}

struct BoardResizeHandle: View {
    @State private var isHovering = false
    @State private var widthAtDragStart: Double?

    let board: BoardState
    let height: Double
    let width: Double
    let onResizeStart: () -> Void
    let onResize: (Double) -> Void
    let onResizeEnd: () -> Void

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(Color.primary.opacity(0.38))
                    .frame(width: 2, height: 34)
                    .opacity(isHovering || widthAtDragStart != nil ? 1 : 0)
            }
            .onHover { isHovering in
                self.isHovering = isHovering
                (isHovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if widthAtDragStart == nil {
                            widthAtDragStart = board.width
                            onResizeStart()
                        }
                        onResize((widthAtDragStart ?? board.width) + value.translation.width)
                    }
                    .onEnded { _ in
                        widthAtDragStart = nil
                        onResizeEnd()
                    }
            )
            .help("Drag to resize board")
            .accessibilityLabel("Resize \(board.displayName) board")
    }
}
