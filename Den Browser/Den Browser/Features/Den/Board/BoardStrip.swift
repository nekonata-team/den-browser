import SwiftUI

private struct BoardStripLayoutKey: Equatable {
    let ids: [UUID]
    let widths: [Double]
    let maximizedBoardID: UUID?
}

struct BoardStrip: View {
    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appearsActive) private var appearsActive

    let size: CGSize
    let shouldShowHeader: Bool
    let profileColor: Color
    let boardSpacing: CGFloat
    let boardHorizontalPadding: CGFloat
    let onOpenBoardAtEnd: (UUID) -> Void

    @State private var boardDrag: BoardDragState?
    @State private var resizingBoardID: UUID?
    @State private var boardFrames: [UUID: CGRect] = [:]
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    @State private var scrollGeometry = BoardStripScrollGeometry.zero
    @State private var didScrollToRestoredFocusedBoard = false
    @State private var pendingBoardAlignment: PendingBoardAlignment?
    @State private var boardCenteringTask: Task<Void, Never>?
    @State private var lastAutoScrollTime = 0.0

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    private var layoutKey: BoardStripLayoutKey {
        let boards = store.isDeskFilterPresented ? store.filteredDeskBoards : store.focusedDesk?.boards ?? []
        return BoardStripLayoutKey(
            ids: boards.map(\.id),
            widths: boards.map(\.width),
            maximizedBoardID: store.maximizedBoardID
        )
    }

    private func isPointerFocusEnabled(for boardID: UUID) -> Bool {
        (boardDrag == nil || boardDrag?.boardID == boardID) && store.temporaryContext == nil
    }

    private var focusedBoardFocusRequest: BoardFocusRequest? {
        guard
            !store.isDenMode,
            !store.isDeskFilterPresented,
            store.temporaryContext == nil,
            let desk = store.focusedDesk,
            let boardID = desk.focusedBoardID
        else { return nil }
        return BoardFocusRequest(deskID: desk.id, boardID: boardID)
    }

    var body: some View {
        let boards =
            store.isDeskFilterPresented
            ? store.filteredDeskBoards
            : store.focusedDesk?.boards ?? []
        let topInset = shouldShowHeader ? DenLayout.denHeaderHeight : DenLayout.outerInset
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
        let focusRequest = focusedBoardFocusRequest
        let alignmentTarget = BoardStripAlignmentTarget(
            deskID: store.presentedDeskID,
            boardID: store.focusedDesk?.focusedBoardID,
            centering: preferences.boardCentering,
            centersFocusedBoard: shouldCenterFocusedBoard,
            restingScrollX: restingScrollX,
            isDeskFilterPresented: store.isDeskFilterPresented,
            layoutKey: layoutKey
        )

        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: boardSpacing) {
                ForEach(boards) { board in
                    boardView(
                        board,
                        width: store.maximizedBoardID == board.id ? maximizedBoardWidth : board.width,
                        height: boardHeight,
                        containerSize: size,
                        focusRequest: focusRequest
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
                    .allowsHitTesting(isPointerFocusEnabled(for: board.id))
                    .accessibilityHidden(!isPointerFocusEnabled(for: board.id))
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
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: layoutKey)
            .transaction(value: store.presentedDeskID) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: BoardStripScrollGeometry.self) { geometry in
            BoardStripScrollGeometry(
                offsetX: geometry.contentOffset.x,
                contentWidth: geometry.contentSize.width,
                containerWidth: geometry.containerSize.width
            )
        } action: { _, geometry in
            scrollGeometry = geometry
            settlePendingBoardAlignment(in: boardFrames)
        }
        .coordinateSpace(name: BoardStripCoordinateSpace.name)
        .scrollIndicators(.never)
        .accessibilityIdentifier("board-strip")
        .onPreferenceChange(BoardFramePreferenceKey.self) { frames in
            boardFrames = frames
            alignDraggedBoard(to: frames)
            settlePendingBoardAlignment(in: frames)
        }
        .onAppear {
            updateBoardLayout(for: size)
            guard !didScrollToRestoredFocusedBoard else { return }
            didScrollToRestoredFocusedBoard = true
            if preferences.boardCentering == .never {
                revealBoard(store.focusedDesk?.focusedBoardID, animated: false)
            } else {
                alignBoardStrip(
                    centersFocusedBoard: shouldCenterFocusedBoard,
                    restingScrollX: restingScrollX,
                    animated: false
                )
            }
        }
        .onChange(of: alignmentTarget) { previous, current in
            guard !current.isDeskFilterPresented else { return }
            guard !previous.isDeskFilterPresented else {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    scrollPosition.scrollTo(x: scrollGeometry.offsetX)
                }
                return
            }
            let animated = previous.deskID == current.deskID
            let focusChanged = previous.boardID != current.boardID
            let layoutChanged = previous.layoutKey != current.layoutKey
            let centeringChanged = previous.centering != current.centering

            if focusChanged {
                let shouldCenter =
                    switch current.centering {
                    case .always: true
                    case .onOverflow: shouldCenterBoardOnOverflow(current.boardID)
                    case .never: false
                    }
                if shouldCenter {
                    if layoutChanged {
                        deferBoardAlignment(.center, current.boardID, animated: animated)
                    } else {
                        centerBoard(current.boardID, animated: animated)
                    }
                } else if layoutChanged {
                    deferBoardAlignment(.visible, current.boardID, animated: animated)
                } else {
                    revealBoard(current.boardID, animated: animated)
                }
            } else if layoutChanged || centeringChanged {
                if current.centering == .never {
                    if layoutChanged {
                        deferBoardAlignment(.visible, current.boardID, animated: animated)
                    } else {
                        revealBoard(current.boardID, animated: animated)
                    }
                } else if current.centersFocusedBoard, layoutChanged {
                    deferBoardAlignment(.center, current.boardID, animated: animated)
                } else {
                    alignBoardStrip(
                        centersFocusedBoard: current.centersFocusedBoard,
                        boardID: current.boardID,
                        restingScrollX: current.restingScrollX,
                        animated: animated
                    )
                }
            } else {
                return
            }
        }
        .onChange(of: store.centerFocusedBoardRequest) { _, _ in
            guard let boardID = store.focusedDesk?.focusedBoardID else { return }
            centerBoard(boardID, animated: true)
        }
        .onChange(of: store.deskFilterSelectionBoardID) { _, boardID in
            guard store.isDeskFilterPresented, let boardID else { return }
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                scrollPosition.scrollTo(id: boardID, anchor: .center)
            }
        }
        .onChange(of: size.width) { _, _ in updateBoardLayout(for: size) }
        .onChange(of: store.boardDragCancellationRequest) { _, _ in cancelBoardDrag() }
        .onChange(of: store.presentedDeskID) { _, deskID in
            if boardDrag?.deskID != deskID { cancelBoardDrag() }
        }
        .onChange(of: store.temporaryContext) { _, context in
            if context != nil { cancelBoardDrag() }
        }
        .onChange(of: appearsActive) { _, isActive in
            if !isActive { cancelBoardDrag() }
        }
    }

    @ViewBuilder
    private func boardView(
        _ board: BoardState,
        width: CGFloat,
        height: CGFloat,
        containerSize: CGSize,
        focusRequest: BoardFocusRequest?
    ) -> some View {
        let focused =
            store.isDeskFilterPresented
            ? board.id == store.deskFilterSelectionBoardID
            : board.id == store.focusedDesk?.focusedBoardID
        let pointerFocusEnabled = !store.isDeskFilterPresented && isPointerFocusEnabled(for: board.id)
        let boardFocusRequest = focusRequest?.boardID == board.id ? focusRequest : nil
        let focus = {
            if store.isDeskFilterPresented {
                store.confirmDeskFilterSelection(board.id)
            } else {
                store.focusBoard(board.id, exitsDenMode: true)
            }
        }

        if board.isTerminal {
            TerminalBoardView(
                board: board,
                isFocused: focused,
                focusRequest: boardFocusRequest,
                isDragging: boardDrag?.boardID == board.id,
                runtime: store.terminalRuntime(for: board),
                profileColor: profileColor,
                width: width,
                height: height,
                isPointerFocusEnabled: pointerFocusEnabled,
                onFocus: focus,
                onRemove: { store.removeBoard(board.id) },
                onDragChanged: { updateBoardDrag(board, value: $0, in: containerSize) },
                onDragEnded: { finishBoardDrag(value: $0, in: containerSize) })
        } else {
            BoardView(
                board: board,
                isFocused: focused,
                focusRequest: boardFocusRequest,
                isDragging: boardDrag?.boardID == board.id,
                runtime: store.runtime(for: board),
                profileColor: profileColor,
                width: width,
                height: height,
                isPointerFocusEnabled: pointerFocusEnabled,
                onFocus: focus,
                onGoToFirst: { store.goToFirstSheetInBoard(board.id) },
                onGoBack: { store.goBackInBoard(board.id) },
                onGoForward: { store.goForwardInBoard(board.id) },
                onRemove: { store.removeBoard(board.id) },
                onDragChanged: { updateBoardDrag(board, value: $0, in: containerSize) },
                onDragEnded: { finishBoardDrag(value: $0, in: containerSize) })
        }
    }

    private func updateBoardLayout(for size: CGSize) {
        store.updateBoardLayout(
            availableWidth: size.width - DenLayout.outerInset * 2,
            spacing: DenLayout.outerInset
        )
    }

    private func updateBoardDrag(
        _ board: BoardState,
        value: DragGesture.Value,
        in size: CGSize
    ) {
        if boardDrag == nil {
            guard
                let desk = store.focusedDesk,
                let frame = boardFrames[board.id],
                store.beginBoardDrag(board.id)
            else { return }
            boardDrag = BoardDragState(
                boardID: board.id,
                deskID: desk.id,
                originalOrder: desk.boards.map(\.id),
                startCenterX: frame.midX
            )
        }

        guard var drag = boardDrag, drag.boardID == board.id else { return }
        drag.translation = value.translation
        drag.offset.height = value.translation.height
        if let frame = boardFrames[board.id] {
            drag.offset.width = drag.desiredCenterX - frame.midX
        }
        boardDrag = drag
        updateBoardInsertion()
        autoScrollBoardStrip(at: value.location, in: size)
    }

    private func updateBoardInsertion() {
        guard var drag = boardDrag, store.focusedDesk?.id == drag.deskID else { return }

        while let boards = store.focusedDesk?.boards,
            let index = store.focusedDesk?.boards.firstIndex(where: { $0.id == drag.boardID }),
            let targetIndex = HorizontalDragInsertion.targetIndex(
                draggedID: drag.boardID,
                orderedIDs: boards.map(\.id),
                desiredCenterX: drag.desiredCenterX,
                frames: boardFrames)
        {
            let crossedBoard = boards[targetIndex]
            store.previewBoardMove(drag.boardID, to: targetIndex)
            let direction = targetIndex > index ? -1.0 : 1.0
            drag.offset.width += direction * (crossedBoard.width + DenLayout.outerInset)
            boardDrag = drag
        }
    }

    private func alignDraggedBoard(to frames: [UUID: CGRect]) {
        guard var drag = boardDrag, let frame = frames[drag.boardID] else { return }
        let offsetX = drag.desiredCenterX - frame.midX
        guard abs(offsetX - drag.offset.width) > 0.5 else { return }
        drag.offset.width = offsetX
        boardDrag = drag
    }

    private func autoScrollBoardStrip(at location: CGPoint, in size: CGSize) {
        guard let drag = boardDrag, let boards = store.focusedDesk?.boards else { return }
        guard
            let decision = HorizontalDragAutoScroll.decision(
                location: location,
                size: size,
                draggedID: drag.boardID,
                orderedIDs: boards.map(\.id),
                edge: 48
            )
        else { return }

        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastAutoScrollTime >= decision.interval else { return }
        lastAutoScrollTime = now
        withAnimation(.linear(duration: shouldReduceMotion ? 0 : 0.14)) {
            scrollPosition.scrollTo(id: decision.targetID, anchor: .center)
        }
    }

    private func finishBoardDrag(value: DragGesture.Value, in size: CGSize) {
        guard boardDrag != nil else { return }
        let isInside =
            value.location.x >= 0 && value.location.x <= size.width
            && value.location.y >= 0 && value.location.y <= size.height
        if isInside {
            store.finishBoardDrag()
            boardDrag = nil
        } else {
            cancelBoardDrag()
        }
    }

    private func cancelBoardDrag() {
        guard let drag = boardDrag else { return }
        let restore = {
            store.restoreBoardOrder(drag.originalOrder, in: drag.deskID)
            store.finishBoardDrag()
            boardDrag = nil
        }
        if shouldReduceMotion {
            restore()
        } else {
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) { restore() }
        }
    }

    private func alignBoardStrip(
        centersFocusedBoard: Bool,
        boardID: UUID? = nil,
        restingScrollX: CGFloat = 0,
        animated: Bool = true
    ) {
        if centersFocusedBoard {
            centerBoard(boardID ?? store.focusedDesk?.focusedBoardID, animated: animated)
        } else {
            resetBoardStripPosition(to: restingScrollX, animated: animated)
        }
    }

    private func resetBoardStripPosition(to horizontalOffset: CGFloat = 0, animated: Bool) {
        pendingBoardAlignment = nil
        boardCenteringTask?.cancel()
        if animated {
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                scrollPosition.scrollTo(x: horizontalOffset)
            }
        } else {
            scrollPosition.scrollTo(x: horizontalOffset)
        }
    }

    private func centerBoard(_ boardID: UUID?, animated: Bool = true) {
        guard resizingBoardID == nil, !store.isBoardDragging, let boardID else { return }
        let boardIDs = Set(store.focusedDesk?.boards.map(\.id) ?? [])
        guard
            boardFrames[boardID] != nil,
            boardIDs.isSubset(of: boardFrames.keys),
            scrollGeometry.containerWidth > 0,
            scrollGeometry.contentWidth > 0
        else {
            pendingBoardAlignment = PendingBoardAlignment(
                boardID: boardID,
                kind: .center,
                animated: animated
            )
            return
        }
        pendingBoardAlignment = nil
        boardCenteringTask?.cancel()
        performBoardCentering(boardID, animated: animated)
    }

    private func revealBoard(_ boardID: UUID?, animated: Bool = true) {
        guard resizingBoardID == nil, !store.isBoardDragging, let boardID else { return }
        let boardIDs = Set(store.focusedDesk?.boards.map(\.id) ?? [])
        guard
            let frame = boardFrames[boardID],
            boardIDs.isSubset(of: boardFrames.keys),
            scrollGeometry.containerWidth > 0,
            scrollGeometry.contentWidth > 0
        else {
            pendingBoardAlignment = PendingBoardAlignment(
                boardID: boardID,
                kind: .visible,
                animated: animated
            )
            return
        }

        guard let targetOffsetX = scrollTargetToRevealBoard(for: frame) else {
            pendingBoardAlignment = nil
            boardCenteringTask?.cancel()
            return
        }

        pendingBoardAlignment = nil
        boardCenteringTask?.cancel()
        performBoardVisibility(targetOffsetX, animated: animated)
    }

    private func deferBoardAlignment(
        _ kind: BoardAlignmentKind,
        _ boardID: UUID?,
        animated: Bool
    ) {
        guard let boardID else { return }
        pendingBoardAlignment = PendingBoardAlignment(
            boardID: boardID,
            kind: kind,
            animated: animated
        )
        boardCenteringTask?.cancel()
        boardCenteringTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            settlePendingBoardAlignment(in: boardFrames)
        }
    }

    private func performBoardCentering(_ boardID: UUID, animated: Bool) {
        guard let frame = boardFrames[boardID] else { return }
        let targetOffsetX = clampedScrollX(scrollGeometry.offsetX + frame.midX - size.width / 2)
        if animated {
            withAnimation(
                DenMotion.spatial(reduceMotion: shouldReduceMotion),
                completionCriteria: .logicallyComplete
            ) {
                scrollPosition.scrollTo(x: targetOffsetX)
            } completion: {
                correctBoardCentering(boardID)
            }
        } else {
            scrollPosition.scrollTo(x: targetOffsetX)
        }
    }

    private func performBoardVisibility(_ targetOffsetX: CGFloat, animated: Bool) {
        if animated {
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                scrollPosition.scrollTo(x: targetOffsetX)
            }
        } else {
            scrollPosition.scrollTo(x: targetOffsetX)
        }
    }

    private func correctBoardCentering(_ boardID: UUID) {
        guard
            !store.isDeskFilterPresented,
            store.focusedDesk?.focusedBoardID == boardID,
            let frame = boardFrames[boardID]
        else { return }
        let correction = frame.midX - size.width / 2
        let targetOffsetX = clampedScrollX(scrollGeometry.offsetX + correction)
        guard abs(targetOffsetX - scrollGeometry.offsetX) > 1 else { return }
        withAnimation(DenMotion.feedback(reduceMotion: shouldReduceMotion)) {
            scrollPosition.scrollTo(x: targetOffsetX)
        }
    }

    private func settlePendingBoardAlignment(in frames: [UUID: CGRect]) {
        let boardIDs = Set(store.focusedDesk?.boards.map(\.id) ?? [])
        guard
            let pending = pendingBoardAlignment,
            let frame = frames[pending.boardID],
            boardIDs.isSubset(of: frames.keys)
                && scrollGeometry.containerWidth > 0
                && scrollGeometry.contentWidth > 0
        else { return }
        self.pendingBoardAlignment = nil
        boardCenteringTask?.cancel()
        boardCenteringTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            switch pending.kind {
            case .center:
                performBoardCentering(pending.boardID, animated: pending.animated)
            case .visible:
                guard let targetOffsetX = scrollTargetToRevealBoard(for: frame) else { return }
                performBoardVisibility(targetOffsetX, animated: pending.animated)
            }
        }
    }

    private func shouldCenterBoardOnOverflow(_ boardID: UUID?) -> Bool {
        guard let boardID, let frame = boardFrames[boardID] else { return true }
        return frame.minX < boardHorizontalPadding
            || frame.maxX > size.width - boardHorizontalPadding
    }

    private func scrollTargetToRevealBoard(for frame: CGRect) -> CGFloat? {
        BoardLayout.scrollTargetToRevealBoard(
            frame: frame,
            currentScrollX: scrollGeometry.offsetX,
            contentWidth: scrollGeometry.contentWidth,
            containerWidth: scrollGeometry.containerWidth,
            horizontalPadding: boardHorizontalPadding
        )
    }

    private func clampedScrollX(_ offset: CGFloat) -> CGFloat {
        min(
            max(0, offset),
            max(0, scrollGeometry.contentWidth - scrollGeometry.containerWidth)
        )
    }
}

private struct BoardStripAlignmentTarget: Equatable {
    let deskID: UUID?
    let boardID: UUID?
    let centering: FocusedBoardCentering
    let centersFocusedBoard: Bool
    let restingScrollX: CGFloat
    let isDeskFilterPresented: Bool
    let layoutKey: BoardStripLayoutKey
}

private enum BoardAlignmentKind {
    case center
    case visible
}

private struct PendingBoardAlignment {
    let boardID: UUID
    let kind: BoardAlignmentKind
    let animated: Bool
}

private struct BoardStripScrollGeometry: Equatable {
    static let zero = BoardStripScrollGeometry(offsetX: 0, contentWidth: 0, containerWidth: 0)

    let offsetX: CGFloat
    let contentWidth: CGFloat
    let containerWidth: CGFloat
}

struct BoardDragState {
    let boardID: UUID
    let deskID: UUID
    let originalOrder: [UUID]
    let startCenterX: CGFloat
    var translation: CGSize = .zero
    var offset: CGSize = .zero

    var desiredCenterX: CGFloat {
        startCenterX + translation.width
    }
}

struct BoardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
            .onHover { isHovering = $0 }
            .pointerStyle(.columnResize)
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
