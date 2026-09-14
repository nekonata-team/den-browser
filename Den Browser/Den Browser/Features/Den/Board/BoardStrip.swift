import SFSafeSymbols
import SwiftUI

struct BoardStripLayoutKey: Equatable {
    let ids: [UUID]
    let widths: [Double]
    let maximizedBoardID: UUID?
    let windowWidth: Double
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
    @State private var revealBoardID: UUID?
    @State private var activatedBoardIDs: Set<UUID> = []
    @State private var visibleBoardIDs: Set<UUID> = []

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
            maximizedBoardID: store.maximizedBoardID,
            windowWidth: size.width
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
        let shouldShowIndicator = !store.isZenViewPresented && boards.count > 1
        let topInset = shouldShowHeader ? DenLayout.denHeaderHeight : DenLayout.outerInset
        let bottomInset = DenLayout.outerInset + (shouldShowIndicator ? DenLayout.boardIndicatorHeight : 0)
        let boardHeight = DenLayout.boardHeight(
            for: size,
            shouldShowHeader: shouldShowHeader,
            shouldShowIndicator: shouldShowIndicator)
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
            deskID: store.presentedDeskID,
            boardID: store.isDeskFilterPresented
                ? store.deskFilterSelectionBoardID
                : store.focusedDesk?.focusedBoardID,
            centering: preferences.boardCentering,
            centersFocusedBoard: shouldCenterFocusedBoard,
            restingScrollX: restingScrollX,
            pendingBoardLinkFocus: store.pendingBoardLinkFocus,
            isDeskFilterPresented: store.isDeskFilterPresented,
            layoutKey: layoutKey
        )

        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: boardSpacing) {
                ForEach(boards) { board in
                    let isFocused = store.focusedDesk?.focusedBoardID == board.id
                    let isVisible = visibleBoardIDs.contains(board.id) || isFocused
                    let isActivated = activatedBoardIDs.contains(board.id) || isVisible

                    boardView(
                        board,
                        size: CGSize(
                            width: store.maximizedBoardID == board.id ? maximizedBoardWidth : board.width,
                            height: boardHeight
                        ),
                        containerSize: size,
                        isActivated: isActivated,
                        isVisible: isVisible
                    )
                    .onScrollVisibilityChange(threshold: 0.05) { visible in
                        if visible {
                            visibleBoardIDs.insert(board.id)
                            activatedBoardIDs.insert(board.id)
                        } else {
                            visibleBoardIDs.remove(board.id)
                        }
                    }
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
                        Image(systemSymbol: .plus)
                            .font(.headline)
                            .frame(
                                width: DenLayout.openBoardAtEndButtonSize,
                                height: DenLayout.openBoardAtEndButtonSize
                            )
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
            .transaction(value: store.isDeskFilterPresented) { transaction in
                if !store.isDeskFilterPresented {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .transaction(value: store.presentedDeskID) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .transaction(value: size.width) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .transaction(value: resizingBoardID != nil) { transaction in
                if resizingBoardID != nil {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
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
        .onScrollPhaseChange { oldPhase, newPhase in
            guard !store.isDeskFilterPresented else { return }
            let wasUserScrolling = oldPhase == .interacting || oldPhase == .decelerating || oldPhase == .tracking
            if wasUserScrolling && newPhase == .idle {
                if let boardID = store.focusedDesk?.focusedBoardID,
                    let centered = centeredBoardScrollX(for: boardID),
                    abs(scrollGeometry.offsetX - centered) < 2.0
                {
                    store.saveDeskScrollOffset(nil, for: store.presentedDeskID)
                } else if scrollGeometry.containerWidth > 0 && scrollGeometry.contentWidth > 0 {
                    store.saveDeskScrollOffset(scrollGeometry.offsetX, for: store.presentedDeskID)
                }
            }
        }
        .coordinateSpace(name: BoardStripCoordinateSpace.name)
        .scrollIndicators(.never)
        .accessibilityIdentifier("board-strip")
        .onChange(of: store.presentedDeskID) { _, deskID in
            activatedBoardIDs.removeAll()
            visibleBoardIDs.removeAll()
            if pendingBoardAlignment?.deskID != deskID {
                cancelPendingBoardAlignment()
            }
        }
        .onPreferenceChange(BoardFramePreferenceKey.self) { frames in
            boardFrames = frames
            alignDraggedBoard(to: frames)
            settlePendingBoardAlignment(in: frames)
        }
        .onAppear {
            updateBoardLayout(for: size)
            guard !didScrollToRestoredFocusedBoard else { return }
            didScrollToRestoredFocusedBoard = true
            let boardID = store.focusedDesk?.focusedBoardID ?? alignmentBoards.first?.id
            if let savedOffset = store.deskScrollOffset(for: store.presentedDeskID) {
                deferBoardAlignment(
                    .resting(savedOffset),
                    boardID,
                    animated: false,
                    layoutKey: layoutKey)
            } else if preferences.boardCentering == .never {
                deferBoardAlignment(
                    .visible,
                    boardID,
                    animated: false,
                    layoutKey: layoutKey)
            } else if shouldCenterFocusedBoard {
                deferBoardAlignment(
                    .center,
                    boardID,
                    animated: false,
                    layoutKey: layoutKey)
            } else {
                deferBoardAlignment(
                    .resting(restingScrollX),
                    boardID,
                    animated: false,
                    layoutKey: layoutKey)
            }
        }
        .onDisappear {
            cancelPendingBoardAlignment()
        }
        .onChange(of: alignmentTarget) { previous, current in
            let focusChanged = previous.boardID != current.boardID
            let deskChanged = previous.deskID != current.deskID
            let layoutChanged = previous.layoutKey != current.layoutKey
            let filterStateChanged = previous.isDeskFilterPresented != current.isDeskFilterPresented
            if focusChanged || deskChanged || layoutChanged || filterStateChanged {
                revealBoardID = nil
            }
            if previous.isDeskFilterPresented && !current.isDeskFilterPresented {
                resetBoardStripPosition(to: scrollGeometry.offsetX, animated: false)
                return
            }
            if current.boardID == nil {
                cancelPendingBoardAlignment()
                return
            }

            if let linkFocus = current.pendingBoardLinkFocus {
                if current.boardID == linkFocus.boardID {
                    scheduleBoardLinkFocusConsumption(linkFocus)
                    return
                }
                scheduleBoardLinkFocusConsumption(linkFocus)
            }

            let isResizing =
                previous.layoutKey.windowWidth != current.layoutKey.windowWidth
                || (previous.layoutKey.ids == current.layoutKey.ids
                    && previous.layoutKey.widths != current.layoutKey.widths)
                || resizingBoardID != nil
            let animated =
                previous.deskID == current.deskID
                && !previous.layoutKey.ids.isEmpty
                && !isResizing
            let centeringChanged = previous.centering != current.centering

            if current.isDeskFilterPresented {
                guard filterStateChanged || focusChanged || layoutChanged else { return }
                if layoutChanged || filterStateChanged {
                    deferBoardAlignment(
                        .center,
                        current.boardID,
                        animated: false,
                        layoutKey: current.layoutKey)
                } else {
                    centerBoard(current.boardID, animated: false)
                }
                return
            }

            if let deskID = current.deskID, let savedOffset = store.deskScrollOffset(for: deskID) {
                if deskChanged || layoutChanged {
                    if let boardID = current.boardID {
                        deferBoardAlignment(
                            .resting(savedOffset),
                            boardID,
                            animated: false,
                            layoutKey: current.layoutKey)
                        return
                    }
                }
            }

            let isInitialAlignment = previous.boardID == nil && current.boardID != nil
            if layoutChanged || isInitialAlignment {
                if current.centering == .never {
                    deferBoardAlignment(
                        .visible,
                        current.boardID,
                        animated: animated,
                        layoutKey: current.layoutKey)
                } else if current.centersFocusedBoard {
                    deferBoardAlignment(
                        .center,
                        current.boardID,
                        animated: animated,
                        layoutKey: current.layoutKey)
                } else {
                    deferBoardAlignment(
                        .resting(current.restingScrollX),
                        current.boardID,
                        animated: animated,
                        layoutKey: current.layoutKey)
                }
            } else if focusChanged {
                let shouldCenter =
                    switch current.centering {
                    case .always: true
                    case .onOverflow: shouldCenterBoardOnOverflow(current.boardID)
                    case .never: false
                    }
                if shouldCenter {
                    centerBoard(current.boardID, animated: animated)
                } else {
                    revealBoard(current.boardID, animated: animated)
                }
            } else if centeringChanged {
                alignBoardStrip(
                    centersFocusedBoard: current.centersFocusedBoard,
                    boardID: current.boardID,
                    restingScrollX: current.restingScrollX,
                    animated: animated
                )
            } else {
                return
            }
        }
        .onChange(of: store.centerFocusedBoardRequest) { _, _ in
            revealBoardID = nil
            guard let boardID = store.focusedDesk?.focusedBoardID else {
                cancelPendingBoardAlignment()
                return
            }
            centerBoard(boardID, animated: true)
        }
        .onChange(of: store.revealPreviousBoardRequest) { _, _ in
            revealPreviousBoard()
        }
        .onChange(of: store.revealNextBoardRequest) { _, _ in
            revealNextBoard()
        }
        .onChange(of: store.isDenMode) { _, _ in
            revealBoardID = nil
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
        size: CGSize,
        containerSize: CGSize,
        isActivated: Bool,
        isVisible: Bool
    ) -> some View {
        let focused =
            store.isDeskFilterPresented
            ? board.id == store.deskFilterSelectionBoardID
            : board.id == store.focusedDesk?.focusedBoardID
        let pointerFocusEnabled = !store.isDeskFilterPresented && isPointerFocusEnabled(for: board.id)
        let boardFocusRequest = focusedBoardFocusRequest?.boardID == board.id ? focusedBoardFocusRequest : nil
        let focus = {
            if store.isDeskFilterPresented {
                store.confirmDeskFilterSelection(board.id)
            } else {
                store.focusBoard(board.id, exitsDenMode: true)
            }
        }

        if !isActivated {
            UnactivatedBoardView(
                board: board,
                isFocused: focused,
                profileColor: profileColor,
                width: size.width,
                height: size.height,
                isPointerFocusEnabled: pointerFocusEnabled,
                onFocus: focus,
                onRemove: { store.removeBoard(board.id) },
                onDragChanged: { updateBoardDrag(board, value: $0, in: containerSize) },
                onDragEnded: { finishBoardDrag(value: $0, in: containerSize) })
        } else if board.isTerminal {
            TerminalBoardView(
                board: board,
                isFocused: focused,
                focusRequest: boardFocusRequest,
                isDragging: boardDrag?.boardID == board.id,
                runtime: store.terminalRuntime(for: board),
                profileColor: profileColor,
                width: size.width,
                height: size.height,
                isPointerFocusEnabled: pointerFocusEnabled,
                isVisibleInViewport: isVisible,
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
                width: size.width,
                height: size.height,
                isPointerFocusEnabled: pointerFocusEnabled,
                isVisibleInViewport: isVisible,
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

    private func scheduleBoardLinkFocusConsumption(_ intent: BoardLinkFocusIntent) {
        DispatchQueue.main.async {
            store.consumeBoardLinkFocus(intent)
        }
    }

    private func resetBoardStripPosition(to horizontalOffset: CGFloat = 0, animated: Bool) {
        cancelPendingBoardAlignment()
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
        let boardIDs = Set(alignmentBoards.map(\.id))
        guard
            boardIDs.contains(boardID),
            boardFrames[boardID] != nil,
            boardIDs.isSubset(of: boardFrames.keys),
            scrollGeometry.containerWidth > 0,
            scrollGeometry.contentWidth > 0,
            abs(scrollGeometry.containerWidth - size.width) <= 1
        else {
            setPendingBoardAlignment(
                PendingBoardAlignment(
                    deskID: store.presentedDeskID,
                    boardID: boardID,
                    kind: .center,
                    animated: animated,
                    layoutKey: layoutKey
                ))
            return
        }
        cancelPendingBoardAlignment()
        performBoardCentering(boardID, animated: animated)
    }

    private func revealBoard(_ boardID: UUID?, animated: Bool = true) {
        guard resizingBoardID == nil, !store.isBoardDragging, let boardID else { return }
        let boardIDs = Set(alignmentBoards.map(\.id))
        guard
            boardIDs.contains(boardID),
            boardFrames[boardID] != nil,
            boardIDs.isSubset(of: boardFrames.keys),
            scrollGeometry.containerWidth > 0,
            scrollGeometry.contentWidth > 0,
            abs(scrollGeometry.containerWidth - size.width) <= 1
        else {
            setPendingBoardAlignment(
                PendingBoardAlignment(
                    deskID: store.presentedDeskID,
                    boardID: boardID,
                    kind: .visible,
                    animated: animated,
                    layoutKey: layoutKey
                ))
            return
        }

        guard let targetOffsetX = revealScrollX(for: boardID) else {
            cancelPendingBoardAlignment()
            return
        }

        cancelPendingBoardAlignment()
        performBoardVisibility(targetOffsetX, animated: animated)
    }

    private func deferBoardAlignment(
        _ kind: BoardAlignmentKind,
        _ boardID: UUID?,
        animated: Bool,
        layoutKey: BoardStripLayoutKey? = nil
    ) {
        guard let boardID else {
            cancelPendingBoardAlignment()
            return
        }
        setPendingBoardAlignment(
            PendingBoardAlignment(
                deskID: store.presentedDeskID,
                boardID: boardID,
                kind: kind,
                animated: animated,
                layoutKey: layoutKey
            ))
    }

    private func performBoardCentering(_ boardID: UUID, animated: Bool) {
        guard let targetOffsetX = centeredBoardScrollX(for: boardID) else { return }
        if animated {
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                scrollPosition.scrollTo(x: targetOffsetX)
            }
        } else {
            scrollPosition.scrollTo(x: targetOffsetX)
        }
    }

    private func centeredBoardScrollX(for boardID: UUID) -> CGFloat? {
        guard
            let boardIndex = alignmentBoards.firstIndex(where: { $0.id == boardID })
        else { return nil }

        let boards = alignmentBoards
        let params = boardLayoutParameters(for: boards)
        return BoardLayout.centeredScrollX(
            for: boardIndex,
            in: params,
            containerWidth: scrollGeometry.containerWidth,
            contentWidth: scrollGeometry.contentWidth
        )
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

    private func settlePendingBoardAlignment(in frames: [UUID: CGRect]) {
        guard
            let pending = pendingBoardAlignment,
            canApplyPendingBoardAlignment(pending, frames: frames)
        else { return }
        cancelPendingBoardAlignment()
        switch pending.kind {
        case .center:
            store.saveDeskScrollOffset(nil, for: pending.deskID)
            performBoardCentering(pending.boardID, animated: pending.animated)
        case .visible:
            guard let targetOffsetX = revealScrollX(for: pending.boardID) else { return }
            store.saveDeskScrollOffset(nil, for: pending.deskID)
            performBoardVisibility(targetOffsetX, animated: pending.animated)
        case .resting(let targetOffsetX):
            resetBoardStripPosition(to: targetOffsetX, animated: pending.animated)
        }
    }

    private func setPendingBoardAlignment(_ pending: PendingBoardAlignment) {
        boardCenteringTask?.cancel()
        pendingBoardAlignment = pending
        boardCenteringTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            settlePendingBoardAlignment(in: boardFrames)
        }
    }

    private func cancelPendingBoardAlignment() {
        pendingBoardAlignment = nil
        boardCenteringTask?.cancel()
        boardCenteringTask = nil
    }

    private func pendingBoardAlignmentIsRelevant(_ pending: PendingBoardAlignment) -> Bool {
        PendingBoardAlignment.isCurrent(pending, in: pendingBoardAlignment)
            && pending.isRelevant(
                to: store.presentedDeskID,
                boardIDs: Set(alignmentBoards.map(\.id)),
                layoutKey: layoutKey)
    }

    private func canApplyPendingBoardAlignment(
        _ pending: PendingBoardAlignment,
        frames: [UUID: CGRect]
    ) -> Bool {
        guard
            pendingBoardAlignmentIsRelevant(pending),
            frames[pending.boardID] != nil,
            Set(alignmentBoards.map(\.id)).isSubset(of: frames.keys),
            scrollGeometry.containerWidth > 0,
            scrollGeometry.contentWidth > 0
        else { return false }
        if let targetWindowWidth = pending.layoutKey?.windowWidth {
            guard abs(scrollGeometry.containerWidth - targetWindowWidth) <= 1 else {
                return false
            }
        }
        return pending.layoutKey == nil || boardFramesMatchLayout(frames)
    }

    private func boardFramesMatchLayout(_ frames: [UUID: CGRect]) -> Bool {
        let boards = alignmentBoards
        let params = boardLayoutParameters(for: boards)
        return boards.enumerated().allSatisfy { index, board in
            guard let frame = frames[board.id] else { return false }
            guard let boardRange = BoardLayout.boardContentRange(for: index, in: params) else {
                return false
            }
            let expectedWidth =
                store.maximizedBoardID == board.id
                ? max(CGFloat(BoardState.minimumWidth), size.width - boardHorizontalPadding * 2)
                : CGFloat(board.width)
            let expectedMinX = boardRange.minX - scrollGeometry.offsetX
            return abs(frame.width - expectedWidth) <= 1
                && abs(frame.minX - expectedMinX) <= 1
        }
    }

    private func shouldCenterBoardOnOverflow(_ boardID: UUID?) -> Bool {
        guard let boardID else { return true }
        return revealScrollX(for: boardID) != nil
    }

    private func revealScrollX(for boardID: UUID) -> CGFloat? {
        guard
            let boardIndex = alignmentBoards.firstIndex(where: { $0.id == boardID })
        else { return nil }

        let boards = alignmentBoards
        return BoardLayout.scrollTargetToRevealBoard(
            for: boardIndex,
            in: boardLayoutParameters(for: boards),
            currentScrollX: scrollGeometry.offsetX,
            contentWidth: scrollGeometry.contentWidth,
            containerWidth: scrollGeometry.containerWidth
        )
    }

    private func revealPreviousBoard() {
        revealBoard(by: -1, edge: .leading)
    }

    private func revealNextBoard() {
        revealBoard(by: 1, edge: .trailing)
    }

    private func revealBoard(by delta: Int, edge: BoardScrollEdge) {
        guard
            !store.isDeskFilterPresented,
            let boards = store.focusedDesk?.boards,
            let focusedBoardID = store.focusedDesk?.focusedBoardID
        else { return }

        let anchorBoardID = revealBoardID ?? focusedBoardID
        guard let anchorIndex = boards.firstIndex(where: { $0.id == anchorBoardID }) else { return }
        let boardIndex = anchorIndex + delta
        guard
            boards.indices.contains(boardIndex),
            let targetOffsetX = boardEdgeScrollX(for: boards[boardIndex].id, edge: edge)
        else { return }

        let boardID = boards[boardIndex].id
        revealBoardID = boardID
        scrollBoardStrip(to: targetOffsetX)
    }

    private func boardEdgeScrollX(for boardID: UUID, edge: BoardScrollEdge) -> CGFloat? {
        guard
            let boards = store.focusedDesk?.boards,
            let boardIndex = boards.firstIndex(where: { $0.id == boardID }),
            let boardRange = BoardLayout.boardContentRange(
                for: boardIndex,
                in: boardLayoutParameters(for: boards)),
            scrollGeometry.containerWidth > 0
        else { return nil }

        let targetOffsetX =
            switch edge {
            case .leading:
                boardRange.minX - boardHorizontalPadding
            case .trailing:
                boardRange.maxX - scrollGeometry.containerWidth + boardHorizontalPadding
            }
        return clampedScrollX(targetOffsetX)
    }

    private func boardLayoutParameters(for boards: [BoardState]) -> BoardLayout.Parameters {
        BoardLayout.Parameters(
            centering: preferences.boardCentering,
            boards: boards,
            maximizedBoardID: store.maximizedBoardID,
            windowWidth: size.width,
            horizontalPadding: boardHorizontalPadding,
            spacing: boardSpacing
        )
    }

    private var alignmentBoards: [BoardState] {
        store.isDeskFilterPresented ? store.filteredDeskBoards : store.focusedDesk?.boards ?? []
    }

    private func scrollBoardStrip(to targetOffsetX: CGFloat) {
        cancelPendingBoardAlignment()
        store.saveDeskScrollOffset(targetOffsetX, for: store.presentedDeskID)
        withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
            scrollPosition.scrollTo(x: targetOffsetX)
        }
    }

    private func clampedScrollX(_ offset: CGFloat) -> CGFloat {
        min(
            max(0, offset),
            max(0, scrollGeometry.contentWidth - scrollGeometry.containerWidth)
        )
    }
}

private enum BoardScrollEdge {
    case leading
    case trailing
}

private struct BoardStripAlignmentTarget: Equatable {
    let deskID: UUID?
    let boardID: UUID?
    let centering: FocusedBoardCentering
    let centersFocusedBoard: Bool
    let restingScrollX: CGFloat
    let pendingBoardLinkFocus: BoardLinkFocusIntent?
    let isDeskFilterPresented: Bool
    let layoutKey: BoardStripLayoutKey
}

enum BoardAlignmentKind {
    case center
    case resting(CGFloat)
    case visible
}

struct PendingBoardAlignment {
    let id: UUID
    let deskID: UUID
    let boardID: UUID
    let kind: BoardAlignmentKind
    let animated: Bool
    let layoutKey: BoardStripLayoutKey?

    init(
        deskID: UUID,
        boardID: UUID,
        kind: BoardAlignmentKind,
        animated: Bool,
        layoutKey: BoardStripLayoutKey?
    ) {
        id = UUID()
        self.deskID = deskID
        self.boardID = boardID
        self.kind = kind
        self.animated = animated
        self.layoutKey = layoutKey
    }

    static func isCurrent(_ request: Self, in pending: Self?) -> Bool {
        pending?.id == request.id
    }

    func isRelevant(to deskID: UUID, boardIDs: Set<UUID>, layoutKey: BoardStripLayoutKey) -> Bool {
        self.deskID == deskID
            && boardIDs.contains(boardID)
            && (self.layoutKey == nil || self.layoutKey == layoutKey)
    }
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
            .accessibilityLabel("Resize \(board.displayName) Board")
            .accessibilityValue("\(Int(board.width.rounded())) points")
            .accessibilityAdjustableAction { direction in
                guard (BoardState.minimumWidth...BoardState.maximumWidth).contains(board.width)
                else { return }
                let delta = direction == .increment ? 80.0 : -80.0
                let adjustedWidth = BoardState.constrainedWidth(board.width + delta)
                guard adjustedWidth != board.width else { return }
                onResizeStart()
                onResize(adjustedWidth)
                onResizeEnd()
            }
    }
}

private struct UnactivatedBoardView: View {
    @Environment(DenStore.self) private var store
    let board: BoardState
    let isFocused: Bool
    let profileColor: Color
    let width: Double
    let height: Double
    let isPointerFocusEnabled: Bool
    let onFocus: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Color.clear
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
                .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
        }
        .shadow(
            color: .black.opacity(isFocused ? 0.42 : 0.30),
            radius: isFocused ? 34 : 24, x: 0, y: 22
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
        .background(store.isDenMode && isFocused ? profileColor.opacity(0.12) : Color.clear)
        .background(.regularMaterial)
    }

    private var dragHandle: some View {
        HStack(spacing: 8) {
            Image(
                systemSymbol: board.isZellij
                    ? .rectangle3Group
                    : (board.isZmx
                        ? .arrowTrianglehead2ClockwiseRotate90
                        : (board.isTerminal ? .appleTerminal : .globe))
            )
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            BoardHeaderTitle(
                board: board,
                isFocused: isFocused,
                isAnchor: store.focusedDesk?.anchorBoardID == board.id
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
        isFocused ? profileColor.opacity(0.75) : Color.primary.opacity(0.16)
    }
}
