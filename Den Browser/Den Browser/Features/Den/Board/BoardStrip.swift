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
    let onAppear: () -> Void
    let onFocusChanged: (BoardFocusTarget, BoardFocusTarget) -> Void
    let onCenterRequest: () -> Void

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    var body: some View {
        let boards = store.focusedDesk?.boards ?? []
        let topInset: CGFloat = shouldShowDeskSwitcher ? 48 : 10
        let bottomInset: CGFloat = 10
        let boardHeight = max(420, size.height - topInset - bottomInset)
        let maximizedBoardWidth = max(280, size.width - boardHorizontalPadding * 2)
        let layoutParams = BoardLayout.Parameters(
            centering: preferences.boardCentering,
            boards: boards,
            maximizedBoardID: store.maximizedBoardID,
            windowWidth: size.width,
            horizontalPadding: boardHorizontalPadding,
            spacing: boardSpacing
        )
        let paddings = BoardLayout.calculatePaddings(for: layoutParams)

        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: boardSpacing) {
                ForEach(boards) { board in
                    BoardView(
                        board: board,
                        isFocused: board.id == store.focusedDesk?.focusedBoardID,
                        isDragging: boardDrag?.boardID == board.id,
                        runtime: store.runtime(for: board),
                        profileColor: profileColor,
                        width: store.maximizedBoardID == board.id ? maximizedBoardWidth : board.width,
                        height: boardHeight,
                        isPointerFocusEnabled: isPointerFocusEnabled(board.id),
                        onFocus: { store.focusBoard(board.id) },
                        onGoBack: { store.goBackInBoard(board.id) },
                        onGoForward: { store.goForwardInBoard(board.id) },
                        onRemove: { store.removeBoard(board.id) },
                        onDragChanged: { onDragChanged(board, $0, size) },
                        onDragEnded: { onDragEnded($0, size) }
                    )
                    .id(board.id)
                    .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.98))
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
                        if store.maximizedBoardID != board.id {
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
        .onAppear(perform: onAppear)
        .onChange(
            of: BoardFocusTarget(
                deskID: store.state.focusedDeskID,
                boardID: store.focusedDesk?.focusedBoardID
            )
        ) { previous, current in
            onFocusChanged(previous, current)
        }
        .onChange(of: store.centerFocusedBoardRequest) { _, _ in
            onCenterRequest()
        }
    }
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
