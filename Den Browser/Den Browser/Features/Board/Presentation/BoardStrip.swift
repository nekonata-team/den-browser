import AppKit
import DenDesign
import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

struct BoardStripLayoutKey: Equatable {
    let ids: [BoardID]
    let widths: [Double]
    let maximizedBoardID: BoardID?
    let windowWidth: Double

    func insertedWidth(
        before boardID: BoardID,
        comparedTo previous: Self,
        spacing: CGFloat
    ) -> CGFloat {
        guard let boardIndex = ids.firstIndex(of: boardID) else { return 0 }

        let previousIDs = Set(previous.ids)
        var insertedWidth: CGFloat = 0
        for index in ids.indices where index < boardIndex {
            guard widths.indices.contains(index), !previousIDs.contains(ids[index]) else { continue }
            insertedWidth += CGFloat(widths[index]) + spacing
        }
        return insertedWidth
    }

    func removedWidth(
        before boardID: BoardID,
        comparedTo current: Self,
        spacing: CGFloat
    ) -> CGFloat {
        guard let boardIndex = ids.firstIndex(of: boardID) else { return 0 }

        let currentIDs = Set(current.ids)
        var removedWidth: CGFloat = 0
        for index in ids.indices where index < boardIndex {
            guard widths.indices.contains(index), !currentIDs.contains(ids[index]) else { continue }
            removedWidth += CGFloat(widths[index]) + spacing
        }
        return removedWidth
    }
}

struct BoardStrip: View {
    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(DeskFilterModel.self) private var deskFilter
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appearsActive) private var appearsActive

    let size: CGSize
    let shouldShowHeader: Bool
    let profileColor: Color
    let boardSpacing: CGFloat
    let boardHorizontalPadding: CGFloat
    let onOpenBoardAtEnd: (BoardID) -> Void

    @State private var boardDrag: BoardDragState?
    @State private var resizingBoardID: BoardID?
    @State private var scrollPosition = ScrollPosition(idType: BoardID.self)
    @State private var scrollGeometry = BoardStripScrollGeometry.zero
    @State private var alignedBoardDeskID: DeskID?
    @State private var pendingBoardActivationAlignment: PendingBoardActivationAlignment?
    @State private var pendingBoardAlignment: PendingBoardAlignment?
    @State private var boardCenteringTask: Task<Void, Never>?
    @State private var lastAutoScrollTime = 0.0
    @State private var revealBoardID: BoardID?
    @State private var activatedBoardIDs: Set<BoardID> = []
    @State private var visibleBoardIDs: Set<BoardID> = []

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    private var layoutKey: BoardStripLayoutKey {
        let boards =
            deskFilter.isPresented ? deskFilter.filteredBoards : controller.focusedDesk?.boards ?? []
        return BoardStripLayoutKey(
            ids: boards.map(\.id),
            widths: boards.map(\.width),
            maximizedBoardID: windowModel.maximizedBoardID,
            windowWidth: size.width
        )
    }

    private func isPointerFocusEnabled(for boardID: BoardID) -> Bool {
        (boardDrag == nil || boardDrag?.boardID == boardID)
            && resizingBoardID == nil
            && windowModel.temporaryContext == nil
    }

    private func isBoardHitTestingEnabled(for boardID: BoardID) -> Bool {
        resizingBoardID == boardID || isPointerFocusEnabled(for: boardID)
    }

    private var focusedBoardFocusRequest: BoardFocusRequest? {
        guard
            !windowModel.isDenMode,
            !deskFilter.isPresented,
            windowModel.temporaryContext == nil,
            let desk = controller.focusedDesk,
            let boardID = desk.focusedBoardID
        else { return nil }
        return BoardFocusRequest(deskID: desk.id, boardID: boardID)
    }

    var body: some View {
        let boards =
            deskFilter.isPresented
            ? deskFilter.filteredBoards
            : controller.focusedDesk?.boards ?? []
        let draggedBoardIDs = draggedGroupBoardIDs
        let shouldShowIndicator = !windowModel.isZenViewPresented && boards.count > 1
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
            maximizedBoardID: windowModel.maximizedBoardID,
            windowWidth: size.width,
            horizontalPadding: boardHorizontalPadding,
            spacing: boardSpacing
        )
        let paddings = BoardLayout.calculatePaddings(for: layoutParams)
        let shouldCenterFocusedBoard = BoardLayout.shouldCenterFocusedBoard(for: layoutParams)
        let restingScrollX = BoardLayout.restingScrollX(for: layoutParams)
        let alignmentTarget = BoardStripAlignmentTarget(
            deskID: controller.presentedDeskID,
            boardID: deskFilter.isPresented
                ? deskFilter.selectionBoardID
                : controller.focusedDesk?.focusedBoardID,
            centering: preferences.boardCentering,
            centersFocusedBoard: shouldCenterFocusedBoard,
            restingScrollX: restingScrollX,
            pendingBoardLinkFocus: windowModel.pendingBoardLinkFocus,
            pendingBoardRemoval: windowModel.pendingBoardRemoval,
            isDeskFilterPresented: deskFilter.isPresented,
            layoutKey: layoutKey
        )

        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: boardSpacing) {
                ForEach(boards) { board in
                    let isFocused = controller.focusedDesk?.focusedBoardID == board.id
                    let isVisible = visibleBoardIDs.contains(board.id) || isFocused
                    let isActivated = activatedBoardIDs.contains(board.id) || isVisible
                    let needsRuntime = isActivated && board.isWeb && controller.webRuntimes[board.id] == nil
                    let isDragging = draggedBoardIDs.contains(board.id)

                    boardView(
                        board,
                        size: CGSize(
                            width: windowModel.maximizedBoardID == board.id ? maximizedBoardWidth : board.width,
                            height: boardHeight
                        ),
                        containerSize: size,
                        isActivated: isActivated,
                        isVisible: isVisible
                    )
                    .task(id: needsRuntime) {
                        guard needsRuntime else { return }
                        _ = controller.webRuntime(for: board)
                    }
                    .onScrollVisibilityChange(threshold: 0.05) { visible in
                        if visible {
                            guard alignedBoardDeskID == controller.presentedDeskID else { return }
                            visibleBoardIDs.insert(board.id)
                            activatedBoardIDs.insert(board.id)
                        } else {
                            visibleBoardIDs.remove(board.id)
                        }
                    }
                    .disabled(deskFilter.isPresented)
                    .overlay {
                        if deskFilter.isPresented {
                            Button {
                                deskFilter.confirmSelection(board.id)
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
                        x: isDragging ? boardDrag?.offset.width ?? 0 : 0,
                        y: isDragging ? boardDrag?.offset.height ?? 0 : 0
                    )
                    .overlay(alignment: .trailing) {
                        if !deskFilter.isPresented && windowModel.maximizedBoardID != board.id {
                            let canResizeWithNextBoard =
                                boards.firstIndex(where: { $0.id == board.id }).map {
                                    $0 + 1 < boards.count
                                } ?? false
                            BoardResizeHandle(
                                board: board,
                                height: boardHeight,
                                width: boardSpacing,
                                canResizeWithNextBoard: canResizeWithNextBoard,
                                onResizeStart: {
                                    cancelPendingBoardAlignment()
                                    resizingBoardID = board.id
                                },
                                onResize: { width, resizeWithNextBoard in
                                    if resizeWithNextBoard {
                                        controller.resizeBoardPair(board.id, to: width)
                                    } else {
                                        controller.resizeBoard(board.id, to: width)
                                    }
                                },
                                onResizeEnd: {
                                    controller.saveBoardWidths()
                                    resizingBoardID = nil
                                }
                            )
                            .offset(x: boardSpacing)
                        }
                    }
                    .allowsHitTesting(isBoardHitTestingEnabled(for: board.id))
                    .accessibilityHidden(!isPointerFocusEnabled(for: board.id))
                    .zIndex(isDragging ? 2 : 1)
                }

                if !deskFilter.isPresented, let lastBoardID = boards.last?.id {
                    BoardStripAddButton(
                        boardHeight: boardHeight,
                        action: { onOpenBoardAtEnd(lastBoardID) }
                    )
                }
            }
            .scrollTargetLayout()
            .padding(.leading, paddings.leading)
            .padding(.trailing, paddings.trailing)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: layoutKey)
            // Keep suppression next to the layout animation. Applying it only on DenView allowed
            // CLI background insertion/removal to animate while compensating the scroll position.
            .transaction(value: windowModel.boardMutationAnimationSuppressionRequest) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .transaction(value: deskFilter.isPresented) { transaction in
                if !deskFilter.isPresented {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .transaction(value: controller.presentedDeskID) { transaction in
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
        .scrollClipDisabled(boardDrag != nil)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: BoardStripScrollGeometry.self) { geometry in
            BoardStripScrollGeometry(
                offsetX: geometry.contentOffset.x + geometry.contentInsets.leading,
                contentWidth: geometry.contentSize.width,
                containerWidth: geometry.containerSize.width,
                leadingContentInset: geometry.contentInsets.leading,
                trailingContentInset: geometry.contentInsets.trailing
            )
        } action: { _, geometry in
            scrollGeometry = geometry
            completePendingBoardActivationAlignment(using: geometry)
            settlePendingBoardAlignment()
            updateDraggedBoardOnScroll(using: geometry)
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            guard !deskFilter.isPresented else { return }
            let wasUserScrolling = oldPhase == .interacting || oldPhase == .decelerating || oldPhase == .tracking
            if wasUserScrolling && newPhase == .idle {
                if let boardID = controller.focusedDesk?.focusedBoardID,
                    let centered = centeredBoardScrollX(for: boardID),
                    abs(scrollGeometry.offsetX - centered) < 2.0
                {
                    controller.saveDeskScrollOffset(nil, for: controller.presentedDeskID)
                } else if scrollGeometry.containerWidth > 0 && scrollGeometry.contentWidth > 0 {
                    controller.saveDeskScrollOffset(scrollGeometry.offsetX, for: controller.presentedDeskID)
                }
            }
        }
        .coordinateSpace(name: BoardStripCoordinateSpace.name)
        .scrollIndicators(.never)
        .accessibilityIdentifier("board-strip")
        .onChange(of: controller.presentedDeskID) { _, deskID in
            alignedBoardDeskID = nil
            pendingBoardActivationAlignment = nil
            activatedBoardIDs.removeAll()
            visibleBoardIDs.removeAll()
            if pendingBoardAlignment?.deskID != deskID {
                cancelPendingBoardAlignment()
            }
        }
        .onAppear {
            updateBoardLayout(for: size)
            guard alignedBoardDeskID != controller.presentedDeskID else { return }
            pendingBoardActivationAlignment = nil
            let boardID = controller.focusedDesk?.focusedBoardID ?? alignmentBoards.first?.id
            guard let boardID else {
                alignedBoardDeskID = controller.presentedDeskID
                return
            }
            if let savedOffset = controller.deskScrollOffset(for: controller.presentedDeskID) {
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
            pendingBoardActivationAlignment = nil
        }
        .onChange(of: alignmentTarget) { previous, current in
            let focusChanged = previous.boardID != current.boardID
            let deskChanged = previous.deskID != current.deskID
            let layoutChanged = previous.layoutKey != current.layoutKey
            let filterStateChanged = previous.isDeskFilterPresented != current.isDeskFilterPresented
            if deskChanged || (previous.boardID == nil && current.boardID != nil) {
                alignedBoardDeskID = nil
                pendingBoardActivationAlignment = nil
            }
            if focusChanged || deskChanged || layoutChanged || filterStateChanged {
                revealBoardID = nil
            }
            if previous.isDeskFilterPresented && !current.isDeskFilterPresented {
                resetBoardStripPosition(to: scrollGeometry.offsetX, animated: false)
                return
            }
            if current.boardID == nil {
                if deskChanged {
                    resetBoardStripPosition(to: 0, animated: false)
                    if alignmentBoards.isEmpty {
                        alignedBoardDeskID = current.deskID
                    }
                } else {
                    cancelPendingBoardAlignment()
                }
                return
            }

            if let linkFocus = current.pendingBoardLinkFocus {
                if current.boardID == linkFocus.boardID {
                    scheduleBoardLinkFocusConsumption(linkFocus)
                    return
                }
                scheduleBoardLinkFocusConsumption(linkFocus)

                if linkFocus.origin == .cli,
                    layoutChanged && !focusChanged,
                    current.layoutKey.ids.count > previous.layoutKey.ids.count,
                    let focusedBoardID = current.boardID
                {
                    let insertedWidth = current.layoutKey.insertedWidth(
                        before: focusedBoardID,
                        comparedTo: previous.layoutKey,
                        spacing: boardSpacing)
                    deferBoardAlignment(
                        .preserveFocusedBoard(scrollGeometry.offsetX + insertedWidth),
                        focusedBoardID,
                        animated: false,
                        layoutKey: current.layoutKey)
                    return
                }
            }

            if let removal = current.pendingBoardRemoval {
                scheduleBoardRemovalConsumption(removal)

                if removal.origin == .cli,
                    layoutChanged && !focusChanged,
                    current.layoutKey.ids.count < previous.layoutKey.ids.count,
                    let focusedBoardID = current.boardID
                {
                    let removedWidth = previous.layoutKey.removedWidth(
                        before: focusedBoardID,
                        comparedTo: current.layoutKey,
                        spacing: boardSpacing)
                    deferBoardAlignment(
                        .preserveFocusedBoard(scrollGeometry.offsetX - removedWidth),
                        focusedBoardID,
                        animated: false,
                        layoutKey: current.layoutKey)
                    return
                }
            }

            let isBoardResizing = resizingBoardID != nil
            let isResizing =
                previous.layoutKey.windowWidth != current.layoutKey.windowWidth
                || (previous.layoutKey.ids == current.layoutKey.ids
                    && previous.layoutKey.widths != current.layoutKey.widths)
                || isBoardResizing
            let animated =
                previous.deskID == current.deskID
                && !previous.layoutKey.ids.isEmpty
                && !isResizing
            let centeringChanged = previous.centering != current.centering

            if isBoardResizing {
                cancelPendingBoardAlignment()
                return
            }

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

            if let deskID = current.deskID, let savedOffset = controller.deskScrollOffset(for: deskID) {
                if deskChanged || (layoutChanged && !focusChanged) {
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
            if deskChanged || layoutChanged || isInitialAlignment {
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
        .onChange(of: windowModel.centerFocusedBoardRequest) { _, _ in
            revealBoardID = nil
            guard let boardID = controller.focusedDesk?.focusedBoardID else {
                cancelPendingBoardAlignment()
                return
            }
            centerBoard(boardID, animated: true)
        }
        .onChange(of: windowModel.revealPreviousBoardRequest) { _, _ in
            revealPreviousBoard()
        }
        .onChange(of: windowModel.revealNextBoardRequest) { _, _ in
            revealNextBoard()
        }
        .onChange(of: windowModel.isDenMode) { _, _ in
            revealBoardID = nil
        }
        .onChange(of: size.width) { _, _ in updateBoardLayout(for: size) }
        .onChange(of: windowModel.boardDragCancellationRequest) { _, _ in cancelBoardDrag() }
        .onChange(of: controller.presentedDeskID) { _, deskID in
            if boardDrag?.deskID != deskID { cancelBoardDrag() }
        }
        .onChange(of: windowModel.temporaryContext) { _, context in
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
        let isDragging = draggedGroupBoardIDs.contains(board.id)
        let focused =
            deskFilter.isPresented
            ? board.id == deskFilter.selectionBoardID
            : board.id == controller.focusedDesk?.focusedBoardID
        let pointerFocusEnabled = !deskFilter.isPresented && isPointerFocusEnabled(for: board.id)
        let boardFocusRequest = focusedBoardFocusRequest?.boardID == board.id ? focusedBoardFocusRequest : nil
        let focus = {
            if deskFilter.isPresented {
                deskFilter.confirmSelection(board.id)
            } else {
                controller.focusBoard(board.id, exitsDenMode: true)
            }
        }

        if !isActivated {
            UnactivatedBoardView(
                board: board,
                isFocused: focused,
                isDragging: isDragging,
                profileColor: profileColor,
                width: size.width,
                height: size.height,
                isPointerFocusEnabled: pointerFocusEnabled,
                onFocus: focus,
                onRemove: { controller.removeBoard(board.id) },
                onDragChanged: { updateBoardDrag(board, value: $0, in: containerSize) },
                onDragEnded: { finishBoardDrag(value: $0, in: containerSize) })
        } else {
            ActivatedBoardView(
                board: board,
                isFocused: focused,
                focusRequest: boardFocusRequest,
                isDragging: isDragging,
                isPointerFocusEnabled: pointerFocusEnabled,
                profileColor: profileColor,
                size: size,
                isVisible: isVisible,
                onFocus: focus,
                onDragChanged: { updateBoardDrag(board, value: $0, in: containerSize) },
                onDragEnded: { finishBoardDrag(value: $0, in: containerSize) }
            )
        }
    }

    private func updateBoardLayout(for size: CGSize) {
        windowModel.updateBoardLayout(
            availableWidth: size.width - DenLayout.outerInset * 2,
            spacing: DenLayout.outerInset
        )
    }

    private var draggedGroupBoardIDs: Set<BoardID> {
        guard let drag = boardDrag,
            let boards = controller.focusedDesk?.boards,
            let group = BoardGroup.containing(drag.boardID, in: boards)
        else { return [] }
        return Set(group.boards.map(\.id))
    }

    private func updateBoardDrag(
        _ board: BoardState,
        value: DragGesture.Value,
        in size: CGSize
    ) {
        let boards = controller.focusedDesk?.boards ?? []
        let frames = calculatedBoardFrames(for: boards)

        if boardDrag == nil {
            guard
                let desk = controller.focusedDesk,
                let frame = frames[board.id],
                controller.beginBoardDrag(board.id)
            else { return }
            boardDrag = BoardDragState(
                boardID: board.id,
                deskID: desk.id,
                originalOrder: desk.boards.map(\.id),
                startCenterX: frame.midX,
                startScrollOffsetX: scrollGeometry.offsetX
            )
        }

        guard var drag = boardDrag, drag.boardID == board.id else { return }
        drag.translation = value.translation
        drag.offset.height = value.translation.height
        if let frame = frames[board.id] {
            let desiredCenterX = drag.desiredContentCenterX(currentScrollOffsetX: scrollGeometry.offsetX)
            drag.offset.width = desiredCenterX - frame.midX
        }
        boardDrag = drag
        updateBoardInsertion()
        autoScrollBoardStrip(at: value.location, in: size)
    }

    private func updateBoardInsertion() {
        guard var drag = boardDrag, controller.focusedDesk?.id == drag.deskID else { return }

        while let boards = controller.focusedDesk?.boards,
            let index = boards.firstIndex(where: { $0.id == drag.boardID }),
            BoardGroup.containing(drag.boardID, in: boards) != nil
        {
            let groups = boardGroups(in: boards)
            let frames = calculatedBoardFrames(for: boards)
            let desiredCenterX = drag.desiredContentCenterX(currentScrollOffsetX: scrollGeometry.offsetX)
            guard
                let targetIndex = HorizontalDragInsertion.groupedTargetIndex(
                    draggedID: drag.boardID,
                    orderedGroups: groups.map { $0.boards.map(\.id) },
                    desiredCenterX: desiredCenterX,
                    frames: frames),
                boards.indices.contains(targetIndex),
                let targetGroup = groups.first(where: { $0.boards.first?.id == boards[targetIndex].id })
            else { break }

            let crossedGroup = targetGroup.boards
            let previousOrder = boards.map(\.id)
            controller.previewBoardMove(drag.boardID, to: BoardIndex(rawValue: targetIndex))
            guard controller.focusedDesk?.boards.map(\.id) != previousOrder else { break }

            let direction = targetIndex > index ? -1.0 : 1.0
            let crossedWidth =
                crossedGroup.reduce(CGFloat.zero) { $0 + CGFloat($1.width) }
                + CGFloat(crossedGroup.count) * DenLayout.outerInset
            drag.offset.width += direction * crossedWidth
            boardDrag = drag
        }
    }

    private func updateDraggedBoardOnScroll(using geometry: BoardStripScrollGeometry) {
        guard var drag = boardDrag else { return }
        let boards = controller.focusedDesk?.boards ?? []
        let frames = calculatedBoardFrames(for: boards)
        if let frame = frames[drag.boardID] {
            let desiredCenterX = drag.desiredContentCenterX(currentScrollOffsetX: geometry.offsetX)
            let newOffsetX = desiredCenterX - frame.midX
            if abs(newOffsetX - drag.offset.width) > 0.5 {
                drag.offset.width = newOffsetX
                boardDrag = drag
                updateBoardInsertion()
            }
        }
    }

    private func calculatedBoardFrames(for boards: [BoardState]) -> [BoardID: CGRect] {
        let params = boardLayoutParameters(for: boards)
        let boardHeight = DenLayout.boardHeight(
            for: size,
            shouldShowHeader: shouldShowHeader,
            shouldShowIndicator: !windowModel.isZenViewPresented && boards.count > 1
        )
        var frames: [BoardID: CGRect] = [:]
        for (index, board) in boards.enumerated() {
            guard let range = BoardLayout.boardContentRange(for: index, in: params) else { continue }
            frames[board.id] = CGRect(
                x: range.minX,
                y: 0,
                width: range.maxX - range.minX,
                height: boardHeight
            )
        }
        return frames
    }

    private func boardGroups(in boards: [BoardState]) -> [BoardGroup] {
        var seen = Set<BoardID>()
        return boards.compactMap { board in
            guard let group = BoardGroup.containing(board.id, in: boards), seen.insert(group.id).inserted else {
                return nil
            }
            return group
        }
    }

    private func autoScrollBoardStrip(at location: CGPoint, in size: CGSize) {
        guard let drag = boardDrag, let boards = controller.focusedDesk?.boards else { return }
        let groupIDs = Set(BoardGroup.containing(drag.boardID, in: boards)?.boards.map(\.id) ?? [drag.boardID])
        guard
            let decision = HorizontalDragAutoScroll.decision(
                location: location,
                size: size,
                draggedID: drag.boardID,
                orderedIDs: boards.map(\.id),
                edge: 48,
                excludingIDs: groupIDs
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
            controller.finishBoardDrag()
            boardDrag = nil
        } else {
            cancelBoardDrag()
        }
    }

    private func cancelBoardDrag() {
        guard let drag = boardDrag else { return }
        let restore = {
            controller.restoreBoardOrder(drag.originalOrder, in: drag.deskID)
            controller.finishBoardDrag()
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
        boardID: BoardID? = nil,
        restingScrollX: CGFloat = 0,
        animated: Bool = true
    ) {
        if centersFocusedBoard {
            centerBoard(boardID ?? controller.focusedDesk?.focusedBoardID, animated: animated)
        } else {
            resetBoardStripPosition(to: restingScrollX, animated: animated)
        }
    }

    private func scheduleBoardLinkFocusConsumption(_ intent: BoardLinkFocusIntent) {
        DispatchQueue.main.async {
            windowModel.consumeBoardLinkFocus(intent)
        }
    }

    private func scheduleBoardRemovalConsumption(_ intent: BoardRemovalIntent) {
        DispatchQueue.main.async {
            windowModel.consumeBoardRemoval(intent)
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

    private func centerBoard(_ boardID: BoardID?, animated: Bool = true) {
        guard resizingBoardID == nil, !windowModel.isBoardDragging, let boardID else { return }
        let boardIDs = Set(alignmentBoards.map(\.id))
        guard
            boardIDs.contains(boardID),
            scrollGeometry.containerWidth > 0,
            scrollGeometry.contentWidth > 0,
            abs(scrollGeometry.containerWidth - size.width) <= 1,
            abs(scrollGeometry.contentWidth - expectedContentWidth(for: alignmentBoards)) <= 1
        else {
            setPendingBoardAlignment(
                PendingBoardAlignment(
                    deskID: controller.presentedDeskID,
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

    private func revealBoard(_ boardID: BoardID?, animated: Bool = true) {
        guard resizingBoardID == nil, !windowModel.isBoardDragging, let boardID else { return }
        let boardIDs = Set(alignmentBoards.map(\.id))
        guard
            boardIDs.contains(boardID),
            scrollGeometry.containerWidth > 0,
            scrollGeometry.contentWidth > 0,
            abs(scrollGeometry.containerWidth - size.width) <= 1,
            abs(scrollGeometry.contentWidth - expectedContentWidth(for: alignmentBoards)) <= 1
        else {
            setPendingBoardAlignment(
                PendingBoardAlignment(
                    deskID: controller.presentedDeskID,
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
        _ boardID: BoardID?,
        animated: Bool,
        layoutKey: BoardStripLayoutKey? = nil
    ) {
        guard let boardID else {
            cancelPendingBoardAlignment()
            return
        }
        setPendingBoardAlignment(
            PendingBoardAlignment(
                deskID: controller.presentedDeskID,
                boardID: boardID,
                kind: kind,
                animated: animated,
                layoutKey: layoutKey
            ))
    }

    private func performBoardCentering(_ boardID: BoardID, animated: Bool) {
        guard let targetOffsetX = centeredBoardScrollX(for: boardID) else { return }
        if animated {
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                scrollPosition.scrollTo(x: targetOffsetX)
            }
        } else {
            scrollPosition.scrollTo(x: targetOffsetX)
        }
    }

    private func centeredBoardScrollX(for boardID: BoardID) -> CGFloat? {
        let boards = alignmentBoards
        guard boards.contains(where: { $0.id == boardID }) else { return nil }
        let params = boardLayoutParameters(for: boards)
        let group = BoardGroup.containing(boardID, in: boards)
        let firstID = group?.boards.first?.id ?? boardID
        let lastID = group?.boards.last?.id ?? boardID
        guard
            let firstIndex = boards.firstIndex(where: { $0.id == firstID }),
            let lastIndex = boards.firstIndex(where: { $0.id == lastID })
        else { return nil }
        return BoardLayout.centeredScrollX(
            for: firstIndex...lastIndex,
            in: params,
            containerWidth: scrollGeometry.containerWidth,
            contentWidth: scrollGeometry.scrollableContentWidth)
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

    private func settlePendingBoardAlignment() {
        guard
            let pending = pendingBoardAlignment,
            canApplyPendingBoardAlignment(pending)
        else { return }
        if alignedBoardDeskID != pending.deskID {
            pendingBoardActivationAlignment = PendingBoardActivationAlignment(
                deskID: pending.deskID,
                layoutKey: pending.layoutKey,
                offsetX: activationAlignmentOffset(for: pending)
            )
        }
        cancelPendingBoardAlignment()
        switch pending.kind {
        case .center:
            controller.saveDeskScrollOffset(nil, for: pending.deskID)
            performBoardCentering(pending.boardID, animated: pending.animated)
        case .visible:
            if let targetOffsetX = revealScrollX(for: pending.boardID) {
                controller.saveDeskScrollOffset(nil, for: pending.deskID)
                performBoardVisibility(targetOffsetX, animated: pending.animated)
            }
        case .resting(let targetOffsetX):
            resetBoardStripPosition(to: targetOffsetX, animated: pending.animated)
        case .preserveFocusedBoard(let targetOffsetX):
            let targetOffsetX = clampedScrollX(targetOffsetX)
            controller.saveDeskScrollOffset(targetOffsetX, for: pending.deskID)
            resetBoardStripPosition(to: targetOffsetX, animated: false)
        }
        completePendingBoardActivationAlignment(using: scrollGeometry)
    }

    private func activationAlignmentOffset(for pending: PendingBoardAlignment) -> CGFloat {
        switch pending.kind {
        case .center:
            centeredBoardScrollX(for: pending.boardID) ?? scrollGeometry.offsetX
        case .resting(let offsetX), .preserveFocusedBoard(let offsetX):
            clampedScrollX(offsetX)
        case .visible:
            revealScrollX(for: pending.boardID) ?? scrollGeometry.offsetX
        }
    }

    private func completePendingBoardActivationAlignment(using geometry: BoardStripScrollGeometry) {
        guard
            let pending = pendingBoardActivationAlignment,
            pending.deskID == controller.presentedDeskID,
            pending.layoutKey == nil || pending.layoutKey == layoutKey
        else { return }
        guard abs(geometry.offsetX - pending.offsetX) <= 1 else { return }

        alignedBoardDeskID = pending.deskID
        pendingBoardActivationAlignment = nil
        let visibleIDs = visibleBoardIDs(in: geometry)
        visibleBoardIDs = visibleIDs
        activatedBoardIDs.formUnion(visibleIDs)
    }

    private func visibleBoardIDs(in geometry: BoardStripScrollGeometry) -> Set<BoardID> {
        guard geometry.containerWidth > 0 else { return [] }

        let boards = alignmentBoards
        let params = boardLayoutParameters(for: boards)
        var visibleIDs = Set<BoardID>()
        for (index, board) in boards.enumerated() {
            guard let range = BoardLayout.boardContentRange(for: index, in: params) else { continue }
            let visibleWidth = max(
                0,
                min(range.maxX, geometry.offsetX + geometry.containerWidth)
                    - max(range.minX, geometry.offsetX))
            guard visibleWidth / (range.maxX - range.minX) >= 0.05 else { continue }
            visibleIDs.insert(board.id)
        }
        return visibleIDs
    }

    private func setPendingBoardAlignment(_ pending: PendingBoardAlignment) {
        boardCenteringTask?.cancel()
        pendingBoardAlignment = pending
        boardCenteringTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            settlePendingBoardAlignment()
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
                to: controller.presentedDeskID,
                boardIDs: Set(alignmentBoards.map(\.id)),
                layoutKey: layoutKey)
    }

    private func canApplyPendingBoardAlignment(_ pending: PendingBoardAlignment) -> Bool {
        guard
            pendingBoardAlignmentIsRelevant(pending),
            scrollGeometry.containerWidth > 0,
            scrollGeometry.contentWidth > 0
        else { return false }
        if let targetWindowWidth = pending.layoutKey?.windowWidth {
            guard abs(scrollGeometry.containerWidth - targetWindowWidth) <= 1 else {
                return false
            }
        }
        return abs(scrollGeometry.contentWidth - expectedContentWidth(for: alignmentBoards)) <= 1
    }

    private func shouldCenterBoardOnOverflow(_ boardID: BoardID?) -> Bool {
        guard let boardID else { return true }
        return revealScrollX(for: boardID) != nil
    }

    private func revealScrollX(for boardID: BoardID) -> CGFloat? {
        guard
            let boardIndex = alignmentBoards.firstIndex(where: { $0.id == boardID })
        else { return nil }

        let boards = alignmentBoards
        return BoardLayout.scrollTargetToRevealBoard(
            for: boardIndex,
            in: boardLayoutParameters(for: boards),
            currentScrollX: scrollGeometry.offsetX,
            contentWidth: scrollGeometry.scrollableContentWidth,
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
            !deskFilter.isPresented,
            let boards = controller.focusedDesk?.boards,
            let focusedBoardID = controller.focusedDesk?.focusedBoardID
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

    private func boardEdgeScrollX(for boardID: BoardID, edge: BoardScrollEdge) -> CGFloat? {
        guard
            let boards = controller.focusedDesk?.boards,
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
            maximizedBoardID: windowModel.maximizedBoardID,
            windowWidth: size.width,
            horizontalPadding: boardHorizontalPadding,
            spacing: boardSpacing
        )
    }

    private func expectedContentWidth(for boards: [BoardState]) -> CGFloat {
        let params = boardLayoutParameters(for: boards)
        return BoardLayout.contentWidth(
            for: params,
            isDeskFilterPresented: deskFilter.isPresented
        )
    }

    private var alignmentBoards: [BoardState] {
        deskFilter.isPresented ? deskFilter.filteredBoards : controller.focusedDesk?.boards ?? []
    }

    private func scrollBoardStrip(to targetOffsetX: CGFloat) {
        cancelPendingBoardAlignment()
        controller.saveDeskScrollOffset(targetOffsetX, for: controller.presentedDeskID)
        withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
            scrollPosition.scrollTo(x: targetOffsetX)
        }
    }

    private func clampedScrollX(_ offset: CGFloat) -> CGFloat {
        min(
            max(0, offset),
            max(0, scrollGeometry.scrollableContentWidth - scrollGeometry.containerWidth)
        )
    }
}

private enum BoardScrollEdge {
    case leading
    case trailing
}

private struct BoardStripAlignmentTarget: Equatable {
    let deskID: DeskID?
    let boardID: BoardID?
    let centering: FocusedBoardCentering
    let centersFocusedBoard: Bool
    let restingScrollX: CGFloat
    let pendingBoardLinkFocus: BoardLinkFocusIntent?
    let pendingBoardRemoval: BoardRemovalIntent?
    let isDeskFilterPresented: Bool
    let layoutKey: BoardStripLayoutKey
}

enum BoardAlignmentKind {
    case center
    case resting(CGFloat)
    case visible
    case preserveFocusedBoard(CGFloat)
}

struct PendingBoardActivationAlignment {
    let deskID: DeskID
    let layoutKey: BoardStripLayoutKey?
    let offsetX: CGFloat
}

struct PendingBoardAlignment {
    let id: UUID
    let deskID: DeskID
    let boardID: BoardID
    let kind: BoardAlignmentKind
    let animated: Bool
    let layoutKey: BoardStripLayoutKey?

    init(
        deskID: DeskID,
        boardID: BoardID,
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

    func isRelevant(to deskID: DeskID, boardIDs: Set<BoardID>, layoutKey: BoardStripLayoutKey) -> Bool {
        self.deskID == deskID
            && boardIDs.contains(boardID)
            && (self.layoutKey == nil || self.layoutKey == layoutKey)
    }
}

private struct BoardStripScrollGeometry: Equatable {
    static let zero = BoardStripScrollGeometry(
        offsetX: 0,
        contentWidth: 0,
        containerWidth: 0,
        leadingContentInset: 0,
        trailingContentInset: 0
    )

    let offsetX: CGFloat
    let contentWidth: CGFloat
    let containerWidth: CGFloat
    let leadingContentInset: CGFloat
    let trailingContentInset: CGFloat

    var scrollableContentWidth: CGFloat {
        contentWidth + leadingContentInset + trailingContentInset
    }
}

struct BoardDragState {
    let boardID: BoardID
    let deskID: DeskID
    let originalOrder: [BoardID]
    let startCenterX: CGFloat
    let startScrollOffsetX: CGFloat
    var translation: CGSize = .zero
    var offset: CGSize = .zero

    func desiredContentCenterX(currentScrollOffsetX: CGFloat) -> CGFloat {
        startCenterX + translation.width + (currentScrollOffsetX - startScrollOffsetX)
    }
}

private struct BoardStripAddButton: View {
    let boardHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
