import DenDesign
import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

struct OverviewView: View {
    let profileColor: Color
    let boardHeight: CGFloat

    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(OverviewModel.self) private var overview
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.appearsActive) private var appearsActive

    @FocusState private var isSearchFocused: Bool
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @State private var scrollPosition = ScrollPosition()
    @State private var overviewDrag: OverviewDragState?
    @State private var overviewGeometry = OverviewGeometry()
    @State private var scrollSize = CGSize.zero
    @State private var lastAutoScrollTime = 0.0
    @State private var hoveredBoardID: BoardID?
    @State private var canvasScale: CGFloat = 1.0
    @State private var pinchStartScale: CGFloat?
    @State private var pinchStartOffset: CGPoint?
    @State private var panStartOffset: CGPoint?
    @State private var rightPanStartOffset: CGPoint?
    @State private var canvasBaseSize = CGSize.zero
    @State private var canvasOffset = CGPoint.zero
    @State private var canvasMargin = CGSize.zero
    @State private var measuredCanvasMargin = CGSize.zero
    @State private var didSetInitialScale = false
    @State private var didCenterInitialSelection = false
    @State private var animateInitialCenter = false
    @State private var centeredSearchQuery: String?
    @State private var measuredCanvasQuery: String?
    @State private var measuredBoardQuery: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 12) {
                Text("Overview")
                    .font(.title3.bold())

                HStack(spacing: 8) {
                    Image(systemSymbol: .magnifyingglass)
                        .foregroundStyle(overview.isFilterInputActive ? .primary : .secondary)
                        .accessibilityHidden(true)

                    TextField(
                        text: Binding(
                            get: { overview.query },
                            set: { overview.setQuery($0) }
                        ),
                        prompt: Text("Search desks and boards")
                    ) {
                        Text("Search desks and boards")
                    }
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .disabled(!overview.isFilterInputActive)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: DenOverviewLayout.searchFieldWidth)
                .background(
                    Color.primary.opacity(overview.isFilterInputActive ? 0.08 : 0.04),
                    in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                        .stroke(
                            overview.isFilterInputActive
                                ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.86))
                                : Color.primary.opacity(0.10),
                            lineWidth: overview.isFilterInputActive ? 1.5 : 1
                        )
                }
                .onTapGesture {
                    if !overview.isFilterInputActive {
                        overview.enterFilterMode()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DenOverviewLayout.contentPadding)
            .padding(.top, DenOverviewLayout.contentPadding)

            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 3, coordinateSpace: .named(OverviewCoordinateSpace.name))
                                .onChanged { value in
                                    if panStartOffset == nil { panStartOffset = canvasOffset }
                                    guard let start = panStartOffset else { return }
                                    scrollCanvas(
                                        to: CGPoint(
                                            x: start.x - value.translation.width, y: start.y - value.translation.height)
                                    )
                                }
                                .onEnded { _ in panStartOffset = nil }
                        )
                    // Lay out at the zoomed size so UI text and symbols render at native resolution.
                    VStack(alignment: .leading, spacing: DenOverviewLayout.deskSpacing * canvasScale) {
                        ForEach(controller.state.desks) { desk in
                            let filtered = desk.boards.filter { board in
                                overview.matchesFilter(board, in: desk)
                            }
                            if overview.query.isEmpty {
                                deskRow(desk, filteredBoards: filtered)
                            } else if !filtered.isEmpty {
                                deskRow(desk, filteredBoards: filtered)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, canvasMargin.width * canvasScale)
                    .padding(.vertical, canvasMargin.height * canvasScale)
                    .onGeometryChange(for: OverviewCanvasMeasurement.self) {
                        OverviewCanvasMeasurement(
                            size: CGSize(width: $0.size.width / canvasScale, height: $0.size.height / canvasScale),
                            margin: canvasMargin, query: overview.query)
                    } action: { measurement in
                        canvasBaseSize = measurement.size
                        measuredCanvasMargin = measurement.margin
                        measuredCanvasQuery = measurement.query
                        centerInitialSelectionIfReady()
                        centerSearchSelectionIfReady()
                    }
                    .animation(
                        DenMotion.spatial(reduceMotion: shouldReduceMotion),
                        value: controller.state.desks.map { $0.boards.map(\.id) })
                }
                .frame(minWidth: scrollSize.width, minHeight: scrollSize.height, alignment: .center)
            }
            .scrollIndicators(.never)
            .scrollPosition($scrollPosition, anchor: .center)
            .coordinateSpace(name: OverviewCoordinateSpace.name)
            .background {
                OverviewCanvasInputSurface(
                    onZoom: { zoomCanvas(by: $0, anchor: $1) },
                    onPan: { translation in
                        guard let translation else {
                            rightPanStartOffset = nil
                            return true
                        }
                        guard windowModel.isOverviewPresented, overviewDrag == nil, didSetInitialScale else {
                            return false
                        }
                        if rightPanStartOffset == nil { rightPanStartOffset = canvasOffset }
                        guard let origin = rightPanStartOffset else { return false }
                        scrollCanvas(to: CGPoint(x: origin.x - translation.width, y: origin.y - translation.height))
                        return true
                    })
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if pinchStartScale == nil {
                            pinchStartScale = canvasScale
                            pinchStartOffset = canvasOffset
                        }
                        let base = pinchStartScale ?? 1.0
                        let newScale = min(max(base * value.magnification, 0.2), DenOverviewLayout.maximumScale)
                        let anchor = CGPoint(
                            x: value.startAnchor.x * scrollSize.width, y: value.startAnchor.y * scrollSize.height)
                        let offset = OverviewCanvasGeometry.zoomOffset(
                            offset: pinchStartOffset ?? canvasOffset, anchor: anchor,
                            contentSize: CGSize(
                                width: canvasBaseSize.width * base, height: canvasBaseSize.height * base),
                            viewportSize: scrollSize, factor: newScale / base)
                        canvasScale = newScale
                        scrollCanvas(to: offset)
                    }
                    .onEnded { _ in
                        pinchStartScale = nil
                        pinchStartOffset = nil
                    }
            )
            .onScrollGeometryChange(for: OverviewScrollGeometry.self) { geometry in
                OverviewScrollGeometry(size: geometry.containerSize, offset: geometry.contentOffset)
            } action: { _, geometry in
                scrollSize = geometry.size
                canvasOffset = geometry.offset
                prepareInitialCanvas()
                centerInitialSelectionIfReady()
            }
            .onPreferenceChange(OverviewBoardFramePreferenceKey.self) {
                overviewGeometry.boardFrames = $0.frames
                measuredBoardQuery = $0.query
                centerInitialSelectionIfReady()
                centerSearchSelectionIfReady()
            }
            .onPreferenceChange(OverviewDeskFramePreferenceKey.self) {
                overviewGeometry.deskFrames = $0
                centerInitialSelectionIfReady()
            }
            .onPreferenceChange(OverviewEmptyBoardFramePreferenceKey.self) {
                overviewGeometry.emptyBoardFrames = $0
                centerInitialSelectionIfReady()
            }
            .onChange(of: windowModel.boardDragCancellationRequest) { _, _ in
                cancelOverviewBoardDrag()
            }
            .onChange(of: windowModel.temporaryContext) { _, context in
                if context != .overview { cancelOverviewBoardDrag() }
            }
            .onChange(of: appearsActive) { _, isActive in
                if !isActive { cancelOverviewBoardDrag() }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    Button {
                        overview.adjustCanvasZoom(by: -1)
                    } label: {
                        Image(systemSymbol: .minus)
                    }
                    .help("Zoom out (-)")
                    .accessibilityLabel("Zoom out")
                    Text(canvasScale, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                    Button {
                        overview.adjustCanvasZoom(by: 1)
                    } label: {
                        Image(systemSymbol: .plus)
                    }
                    .help("Zoom in (=)")
                    .accessibilityLabel("Zoom in")
                    Divider().frame(height: 14)
                    Button {
                        overview.returnToCurrentDesk()
                    } label: {
                        Image(systemSymbol: .arrowCounterclockwise)
                    }
                    .help("Return to current Desk")
                    .accessibilityLabel("Return to current Desk")
                }
                .buttonStyle(.borderless)
                .padding(10)
                .glassEffect(.regular, in: Capsule())
                .disabled(overviewDrag != nil)
                .padding(12)
            }
            .overlay(alignment: .topLeading) {
                if let drag = overviewDrag, let board = draggedOverviewBoard {
                    OverviewBoardCard(
                        board: board,
                        isSelected: true,
                        profileColor: profileColor,
                        boardHeight: boardHeight,
                        differentiateWithoutColor: differentiateWithoutColor,
                        thumbnail: controller.thumbnailCache.image(for: board.id),
                        scale: canvasScale
                    )
                    .scaleEffect(shouldReduceMotion ? 1 : 1.03)
                    .shadow(color: .black.opacity(0.32), radius: 18, y: 10)
                    .position(drag.previewCenter)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if let target = overviewDropTarget {
                    Capsule()
                        .fill(profileColor)
                        .frame(width: 3, height: target.height)
                        .position(x: target.lineX, y: target.lineY)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if !hasOverviewMatches {
                    ContentUnavailableView.search(text: overview.query)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .overlay(alignment: .topTrailing) {
            DenCloseButton(label: "Close Overview") {
                windowModel.hideOverview()
            }
            .padding(DenOverviewLayout.closeButtonInset)
        }
        .onExitCommand {
            windowModel.hideOverview()
        }
        .onChange(of: overview.isFilterInputActive) { _, newValue in
            isSearchFocused = newValue
        }
        .onChange(of: overview.query) { _, newValue in
            if isSearchFocused {
                TextInputComposition.syncActiveFieldEditor(to: newValue)
            }
        }
        .onChange(of: overview.selectionBoardID) { _, boardID in
            scrollToSelection(boardID)
        }
        .onChange(of: overview.selectionDeskID) { _, _ in
            if overview.selectionBoardID == nil { scrollToSelection(nil) }
        }
        .onChange(of: overview.canvasZoomSteps) { old, new in
            zoomCanvas(
                by: pow(1.2, CGFloat(new - old)), anchor: CGPoint(x: scrollSize.width / 2, y: scrollSize.height / 2))
        }
        .onChange(of: overview.canvasResetRequest) { _, _ in
            animateInitialCenter = true
            didSetInitialScale = false
            didCenterInitialSelection = false
            prepareInitialCanvas()
            centerInitialSelectionIfReady()
        }
        .onAppear {
            prepareInitialCanvas()
        }
    }

    private func scrollToSelection(_ boardID: BoardID?, animated: Bool = true) {
        guard measuredCanvasQuery == overview.query, boardID == nil || measuredBoardQuery == overview.query else {
            return
        }
        guard
            let frame = boardID.flatMap({ overviewGeometry.boardFrames[$0] })
                ?? overview.selectionDeskID.flatMap({
                    overviewGeometry.emptyBoardFrames[$0] ?? overviewGeometry.deskFrames[$0]
                })
        else { return }
        centerCanvas(on: frame, animated: animated)
    }

    private func centerCanvas(on frame: CGRect, animated: Bool = true) {
        withAnimation(animated ? DenMotion.spatial(reduceMotion: shouldReduceMotion) : nil) {
            scrollCanvas(
                to: CGPoint(
                    x: canvasOffset.x + frame.midX - scrollSize.width / 2,
                    y: canvasOffset.y + frame.midY - scrollSize.height / 2))
        }
    }

    private func prepareInitialCanvas() {
        guard !didSetInitialScale, scrollSize.width > 0, scrollSize.height > 0, boardHeight > 0 else { return }
        let board = controller.state.desks.lazy.flatMap(\.boards).first { $0.id == overview.selectionBoardID }
        let size = CGSize(
            width: board.map { CGFloat($0.width) * DenOverviewLayout.boardCardHeight / boardHeight }
                ?? DenOverviewLayout.emptyBoardWidth,
            height: DenOverviewLayout.boardCardHeight)
        let rowHeight = captionSize * 1.2 + 4 + DenOverviewLayout.boardCardHeight
        let neighborhoodHeight = rowHeight * 3 + DenOverviewLayout.deskSpacing * 2
        canvasScale = min(
            max(
                OverviewCanvasGeometry.initialScale(
                    boardSize: size, neighborhoodHeight: neighborhoodHeight, viewportSize: scrollSize), 0.2),
            DenOverviewLayout.maximumScale)
        canvasMargin = CGSize(
            width: scrollSize.width / (2 * canvasScale), height: scrollSize.height / (2 * canvasScale))
        didSetInitialScale = true
    }

    private func centerInitialSelectionIfReady() {
        guard didSetInitialScale, !didCenterInitialSelection, measuredCanvasMargin == canvasMargin,
            measuredCanvasQuery == overview.query,
            overview.selectionBoardID == nil || measuredBoardQuery == overview.query,
            let frame = overview.selectionBoardID.flatMap({ overviewGeometry.boardFrames[$0] })
                ?? overview.selectionDeskID.flatMap({ overviewGeometry.emptyBoardFrames[$0] }),
            abs(frame.height - DenOverviewLayout.boardCardHeight * canvasScale) < 0.5
        else { return }
        didCenterInitialSelection = true
        scrollToSelection(overview.selectionBoardID, animated: animateInitialCenter)
    }

    private func centerSearchSelectionIfReady() {
        guard measuredCanvasQuery == overview.query, measuredBoardQuery == overview.query,
            centeredSearchQuery != overview.query
        else { return }
        centeredSearchQuery = overview.query
        if !overview.query.isEmpty { scrollToSelection(overview.selectionBoardID) }
    }

    private func scrollCanvas(to offset: CGPoint) {
        let target = OverviewCanvasGeometry.clampedOffset(
            offset,
            contentSize: CGSize(width: canvasBaseSize.width * canvasScale, height: canvasBaseSize.height * canvasScale),
            viewportSize: scrollSize)
        scrollPosition.scrollTo(x: target.x, y: target.y)
    }

    @discardableResult
    private func zoomCanvas(by factor: CGFloat, anchor: CGPoint) -> Bool {
        guard windowModel.isOverviewPresented, overviewDrag == nil, didSetInitialScale else { return false }
        let nextScale = min(max(canvasScale * factor, 0.2), DenOverviewLayout.maximumScale)
        let offset = OverviewCanvasGeometry.zoomOffset(
            offset: canvasOffset, anchor: anchor,
            contentSize: CGSize(width: canvasBaseSize.width * canvasScale, height: canvasBaseSize.height * canvasScale),
            viewportSize: scrollSize, factor: nextScale / canvasScale)
        canvasScale = nextScale
        scrollCanvas(to: offset)
        return true
    }

    private var hasOverviewMatches: Bool {
        overview.query.isEmpty
            || controller.state.desks.contains { desk in
                desk.boards.contains { overview.matchesFilter($0, in: desk) }
            }
    }

    private func deskRow(_ desk: DeskState, filteredBoards: [BoardState]) -> some View {
        VStack(alignment: .leading, spacing: 4 * canvasScale) {
            HStack(spacing: 8 * canvasScale) {
                Text(desk.label)
                    .font(.system(size: captionSize * canvasScale, weight: .semibold))

                if desk.id == overview.selectionDeskID {
                    Circle()
                        .fill(profileColor)
                        .frame(
                            width: DenOverviewLayout.selectionIndicatorSize * canvasScale,
                            height: DenOverviewLayout.selectionIndicatorSize * canvasScale
                        )
                        .overlay {
                            if differentiateWithoutColor {
                                Circle()
                                    .stroke(Color.primary, lineWidth: canvasScale)
                            }
                        }
                }
            }
            .frame(height: captionSize * 1.2 * canvasScale)
            .foregroundStyle(Color.primary.opacity(desk.id == overview.selectionDeskID ? 0.96 : 0.58))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Desk \(desk.label)")
            .accessibilityValue(desk.id == overview.selectionDeskID ? "Selected Desk" : "")
            .accessibilityAddTraits(desk.id == overview.selectionDeskID ? .isSelected : [])

            HStack(alignment: .top, spacing: DenOverviewLayout.boardSpacing * canvasScale) {
                if filteredBoards.isEmpty {
                    OverviewEmptyDeskCard(
                        desk: desk,
                        scale: canvasScale,
                        onSelect: { overview.selectDesk(desk.id) },
                        onEnter: { overview.enterDesk(desk.id) }
                    )
                } else {
                    ForEach(filteredBoards) { board in
                        overviewBoard(board, in: desk)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview-desk.\(desk.id.rawValue.uuidString.lowercased())")
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: OverviewDeskFramePreferenceKey.self,
                    value: [desk.id: proxy.frame(in: .named(OverviewCoordinateSpace.name))])
            }
        }
        .id(desk.id)
    }

    private func overviewBoard(_ board: BoardState, in desk: DeskState) -> some View {
        let isSelected = desk.id == overview.selectionDeskID && board.id == overview.selectionBoardID
        return ZStack(alignment: .topTrailing) {
            Button {
                overview.selectBoard(board.id)
            } label: {
                OverviewBoardCard(
                    board: board,
                    isSelected: isSelected,
                    isAnchor: desk.anchorBoardID == board.id,
                    profileColor: profileColor,
                    boardHeight: boardHeight,
                    differentiateWithoutColor: differentiateWithoutColor,
                    thumbnail: controller.thumbnailCache.image(for: board.id),
                    scale: canvasScale
                )
            }
            .buttonStyle(.plain)

            if hoveredBoardID == board.id && overviewDrag == nil {
                OverviewBoardCloseButton(boardName: board.displayName, scale: canvasScale) {
                    controller.removeBoard(board.id)
                }
                .padding(DenOverviewLayout.boardCloseButtonPadding * canvasScale)
            }
        }
        .task(id: board.id) { await controller.thumbnailCache.loadThumbnail(for: board.id) }
        .onHover { isHovering in
            if isHovering {
                if hoveredBoardID != board.id {
                    hoveredBoardID = board.id
                }
            } else if hoveredBoardID == board.id {
                hoveredBoardID = nil
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: OverviewBoardFramePreferenceKey.self,
                    value: OverviewBoardFrames(
                        query: overview.query, frames: [board.id: proxy.frame(in: .named(OverviewCoordinateSpace.name))]
                    ))
            }
        }
        .opacity(overviewDrag?.boardID == board.id ? 0 : 1)
        .highPriorityGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(OverviewCoordinateSpace.name))
                .onChanged { updateOverviewBoardDrag(board, value: $0) }
                .onEnded { finishOverviewBoardDrag(value: $0) }
        )
        .allowsHitTesting(overviewDrag == nil || overviewDrag?.boardID == board.id)
        .zIndex(overviewDrag?.boardID == board.id ? 2 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(overviewBoardAccessibilityLabel(for: board, in: desk))
        .accessibilityValue(isSelected ? "Selected Board" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("overview-board.\(board.id.rawValue.uuidString.lowercased())")
        .accessibilityHint("Drag to move this Board, or use Board movement actions")
        .accessibilityAction(named: "Enter Board") {
            overview.enterBoard(board.id)
        }
        .accessibilityAction(named: "Remove Board") {
            controller.removeBoard(board.id)
        }
        .accessibilityAction(named: "Move Board Left") {
            overview.selectBoard(board.id)
            overview.moveSelectionBoardLeft()
        }
        .accessibilityAction(named: "Move Board Right") {
            overview.selectBoard(board.id)
            overview.moveSelectionBoardRight()
        }
        .accessibilityAction(named: "Move Board to Previous Desk") {
            overview.selectBoard(board.id)
            overview.moveSelectionBoardToPreviousDesk()
        }
        .accessibilityAction(named: "Move Board to Next Desk") {
            overview.selectBoard(board.id)
            overview.moveSelectionBoardToNextDesk()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                overview.enterBoard(board.id)
            }
        )
        .id(board.id)
    }

    private func overviewBoardAccessibilityLabel(for board: BoardState, in desk: DeskState) -> String {
        let detail: String?
        if let zmxSessionName = board.zmxSessionName {
            detail = "zmx session \(zmxSessionName)"
        } else if let zellijSessionName = board.zellijSessionName {
            detail = "Zellij session \(zellijSessionName)"
        } else if let terminalWorkingDirectory = board.terminalWorkingDirectory {
            detail = "Terminal working directory \(terminalWorkingDirectory)"
        } else if let currentSheetURL = board.currentSheetURL {
            detail = "Sheet URL \(currentSheetURL.absoluteString)"
        } else {
            detail = nil
        }

        let isAnchor = desk.anchorBoardID == board.id
        return [
            isAnchor ? "Anchor board" : nil,
            OverviewBoardCard.kindLabel(for: board) + " Board \(board.displayName)",
            detail,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func updateOverviewBoardDrag(_ board: BoardState, value: DragGesture.Value) {
        if overviewDrag == nil {
            guard
                let frame = overviewGeometry.boardFrames[board.id],
                windowModel.beginOverviewBoardDrag(board.id)
            else { return }
            overviewDrag = OverviewDragState(
                boardID: board.id,
                location: value.location,
                pointerToCenter: CGSize(
                    width: frame.midX - value.startLocation.x,
                    height: frame.midY - value.startLocation.y))
        }

        guard var drag = overviewDrag, drag.boardID == board.id else { return }
        drag.location = value.location
        overviewDrag = drag
        autoScrollOverview(at: value.location)
    }

    private func finishOverviewBoardDrag(value: DragGesture.Value) {
        guard let drag = overviewDrag else { return }
        guard let target = overviewInsertionTarget(at: value.location) else {
            overview.cancelBoardDrag()
            overviewDrag = nil
            return
        }
        overview.finishBoardDrag(
            drag.boardID, toDeskID: target.deskID, at: target.index)
        overviewDrag = nil
    }

    private func cancelOverviewBoardDrag() {
        guard overviewDrag != nil else { return }
        overview.cancelBoardDrag()
        overviewDrag = nil
    }

    private var overviewDropTarget: OverviewDropTarget? {
        guard
            let drag = overviewDrag,
            let target = overviewInsertionTarget(at: drag.location),
            let desk = controller.state.desks.first(where: { $0.id == target.deskID })
        else {
            return nil
        }

        let orderedBoardIDs = desk.boards.map(\.id).filter { $0 != drag.boardID }
        if let referenceID = orderedBoardIDs.indices.contains(target.index.rawValue)
            ? orderedBoardIDs[target.index.rawValue]
            : orderedBoardIDs.last,
            let frame = overviewGeometry.boardFrames[referenceID]
        {
            let isBeforeReference = target.index.rawValue < orderedBoardIDs.count
            return OverviewDropTarget(
                lineX: isBeforeReference
                    ? frame.minX - DenOverviewLayout.boardSpacing * canvasScale / 2
                    : frame.maxX + DenOverviewLayout.boardSpacing * canvasScale / 2,
                lineY: frame.midY,
                height: frame.height + 8)
        } else if let frame = overviewGeometry.emptyBoardFrames[desk.id] {
            return OverviewDropTarget(
                lineX: frame.minX - DenOverviewLayout.boardSpacing * canvasScale / 2,
                lineY: frame.midY,
                height: frame.height + 8)
        } else {
            return nil
        }
    }

    private func overviewInsertionTarget(at location: CGPoint) -> (deskID: DeskID, index: BoardIndex)? {
        guard
            let drag = overviewDrag,
            scrollBounds.contains(location),
            let deskID = OverviewDragGeometry.targetDeskID(
                at: location,
                frames: overviewGeometry.deskFrames),
            let desk = controller.state.desks.first(where: { $0.id == deskID }),
            let index = OverviewDragGeometry.targetIndex(
                draggedID: drag.boardID,
                orderedIDs: desk.boards.map(\.id),
                locationX: location.x,
                frames: overviewGeometry.boardFrames)
        else { return nil }
        return (deskID, BoardIndex(rawValue: index))
    }

    private func autoScrollOverview(at location: CGPoint) {
        guard scrollBounds.contains(location) else { return }

        let leadingDistance = min(location.x, location.y)
        let trailingDistance = min(scrollSize.width - location.x, scrollSize.height - location.y)
        let isLeading = leadingDistance < trailingDistance
        let distanceToEdge = isLeading ? leadingDistance : trailingDistance
        guard distanceToEdge < 48 else { return }

        let now = Date.timeIntervalSinceReferenceDate
        let interval = distanceToEdge < 16 ? 0.06 : 0.16
        guard now - lastAutoScrollTime >= interval else { return }
        lastAutoScrollTime = now

        let horizontal = min(location.x, scrollSize.width - location.x)
        let vertical = min(location.y, scrollSize.height - location.y)
        if horizontal <= vertical,
            let deskID = OverviewDragGeometry.targetDeskID(
                at: location,
                frames: overviewGeometry.deskFrames),
            let desk = controller.state.desks.first(where: { $0.id == deskID }),
            let boardID = (isLeading ? desk.boards.first : desk.boards.last)?.id
        {
            withAnimation(.linear(duration: shouldReduceMotion ? 0 : 0.14)) {
                scrollToSelection(boardID)
            }
        } else if let deskID = nearestDeskID(to: location.y, leading: isLeading) {
            withAnimation(.linear(duration: shouldReduceMotion ? 0 : 0.14)) {
                if let frame = overviewGeometry.deskFrames[deskID] { centerCanvas(on: frame) }
            }
        }
    }

    private func nearestDeskID(to locationY: CGFloat, leading: Bool) -> DeskID? {
        let desks = controller.state.desks
        guard
            let currentDeskID = OverviewDragGeometry.targetDeskID(
                at: CGPoint(x: 0, y: locationY),
                frames: overviewGeometry.deskFrames),
            let currentIndex = desks.firstIndex(where: { $0.id == currentDeskID })
        else { return nil }
        let targetIndex = currentIndex + (leading ? -1 : 1)
        guard desks.indices.contains(targetIndex) else { return nil }
        return desks[targetIndex].id
    }

    private var scrollBounds: CGRect {
        CGRect(origin: .zero, size: scrollSize)
    }

    private var draggedOverviewBoard: BoardState? {
        guard let boardID = overviewDrag?.boardID else { return nil }
        return controller.state.desks.lazy.compactMap { desk in
            desk.boards.first(where: { $0.id == boardID })
        }.first
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}

private enum DenOverviewLayout {
    static let maximumScale: CGFloat = 3
    static let contentPadding: CGFloat = 18
    static let closeButtonInset: CGFloat = 14
    static let searchFieldWidth: CGFloat = 320
    static let selectionIndicatorSize: CGFloat = 6
    static let emptyBoardWidth: CGFloat = 150
    static let boardCardHeight: CGFloat = 120
    static let boardSpacing: CGFloat = 10
    static let deskSpacing: CGFloat = 12
    static let boardPadding: CGFloat = 10
    static let widthIndicatorHeight: CGFloat = 5
    static let boardCloseButtonSize: CGFloat = 18
    static let boardCloseButtonPadding: CGFloat = 6
}

private struct OverviewBoardCloseButton: View {
    let boardName: String
    var scale: CGFloat = 1
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onRemove) {
            Image(systemSymbol: .xmark)
                .font(.system(size: 9 * scale, weight: .bold))
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .frame(
                    width: DenOverviewLayout.boardCloseButtonSize * scale,
                    height: DenOverviewLayout.boardCloseButtonSize * scale
                )
                .background(
                    isHovered ? Color.primary.opacity(0.20) : Color.primary.opacity(0.10),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Remove Board")
        .accessibilityLabel("Remove Board \(boardName)")
    }
}

private enum DenOverviewColors {
    static let web = Color.blue
    static let terminal = Color.orange
    static let tutorial = Color.purple
}

private struct OverviewDragState {
    let boardID: BoardID
    var location: CGPoint
    let pointerToCenter: CGSize

    var previewCenter: CGPoint {
        CGPoint(
            x: location.x + pointerToCenter.width,
            y: location.y + pointerToCenter.height)
    }
}

private struct OverviewGeometry {
    var boardFrames: [BoardID: CGRect] = [:]
    var deskFrames: [DeskID: CGRect] = [:]
    var emptyBoardFrames: [DeskID: CGRect] = [:]
}

private struct OverviewScrollGeometry: Equatable {
    let size: CGSize
    let offset: CGPoint
}

private nonisolated struct OverviewCanvasMeasurement: Equatable, Sendable {
    let size: CGSize
    let margin: CGSize
    let query: String
}

private struct OverviewDropTarget {
    let lineX: CGFloat
    let lineY: CGFloat
    let height: CGFloat
}

private enum OverviewCoordinateSpace {
    static let name = "overview"
}

private struct OverviewBoardFrames: Equatable {
    var query: String?
    var frames: [BoardID: CGRect] = [:]
}

private struct OverviewBoardFramePreferenceKey: PreferenceKey {
    static let defaultValue = OverviewBoardFrames()

    static func reduce(value: inout OverviewBoardFrames, nextValue: () -> OverviewBoardFrames) {
        let next = nextValue()
        if let query = next.query { value.query = query }
        value.frames.merge(next.frames, uniquingKeysWith: { $1 })
    }
}

private struct OverviewDeskFramePreferenceKey: PreferenceKey {
    static let defaultValue: [DeskID: CGRect] = [:]

    static func reduce(value: inout [DeskID: CGRect], nextValue: () -> [DeskID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct OverviewEmptyBoardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [DeskID: CGRect] = [:]

    static func reduce(value: inout [DeskID: CGRect], nextValue: () -> [DeskID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct OverviewEmptyDeskCard: View {
    let desk: DeskState
    var scale: CGFloat = 1
    let onSelect: () -> Void
    let onEnter: () -> Void
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12

    var body: some View {
        Button(action: onSelect) {
            Text("Empty")
                .font(.system(size: captionSize * scale))
                .foregroundStyle(.secondary)
                .frame(
                    width: DenOverviewLayout.emptyBoardWidth * scale,
                    height: DenOverviewLayout.boardCardHeight * scale
                )
                .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(
                        cornerRadius: DenRadius.small * scale,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: OverviewEmptyBoardFramePreferenceKey.self,
                    value: [desk.id: proxy.frame(in: .named(OverviewCoordinateSpace.name))])
            }
        }
        .accessibilityLabel("Empty Desk \(desk.label)")
        .accessibilityHint("Double-click to enter this Desk")
        .accessibilityAddTraits(.isButton)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded(onEnter)
        )
    }
}

struct OverviewBoardCard: View {
    let board: BoardState
    let isSelected: Bool
    var isAnchor: Bool = false
    let profileColor: Color
    let boardHeight: CGFloat
    let differentiateWithoutColor: Bool
    var thumbnail: NSImage?
    var scale: CGFloat = 1
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var caption2Size: CGFloat = 11

    static func kindLabel(for board: BoardState) -> String {
        if board.isInspection { return "Inspection" }
        if board.isTutorial { return "Tutorial" }
        if board.isZmx { return "zmx" }
        if board.isZellij { return "Zellij" }
        if board.isTerminal { return "Terminal" }
        return "Web"
    }

    private var cardWidth: CGFloat {
        CGFloat(board.width) * DenOverviewLayout.boardCardHeight / boardHeight * scale
    }

    private var boardTypeIcon: some View {
        Image(systemSymbol: boardSymbol(for: board.kind))
            .font(.system(size: captionSize * scale, weight: .semibold))
            .foregroundStyle(typeColor)
    }

    private var typeColor: Color {
        if board.isInspection { return .purple }
        if board.isTutorial { return DenOverviewColors.tutorial }
        return board.isTerminal ? DenOverviewColors.terminal : DenOverviewColors.web
    }

    private var backgroundColor: Color {
        if isSelected { return (differentiateWithoutColor ? Color.primary : profileColor).opacity(0.18) }
        return typeColor.opacity(0.09)
    }

    private var detailText: String {
        if board.isTutorial { return "Interactive checklist" }
        return board.zmxSessionName
            ?? board.zellijSessionName
            ?? board.terminalWorkingDirectory
            ?? board.currentSheetURL?.host(percentEncoded: false)
            ?? board.currentSheetURL?.absoluteString
            ?? ""
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cardWidth, height: DenOverviewLayout.boardCardHeight * scale, alignment: .center)
                    .clipped()
                    .opacity(0.85)

                // Subdued bottom gradient overlay for readability of board label
                VStack {
                    Spacer()
                    HStack(spacing: 4 * scale) {
                        boardTypeIcon
                        Text(board.displayName)
                            .font(.system(size: caption2Size * scale, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        if isAnchor {
                            Image(systemSymbol: .pinFill)
                                .font(.system(size: caption2Size * scale))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 4 * scale)
                    .background(Color.black.opacity(0.6))
                }
            } else {
                VStack(alignment: .leading, spacing: 6 * scale) {
                    HStack(spacing: 6 * scale) {
                        boardTypeIcon
                            .accessibilityHidden(true)

                        Text(Self.kindLabel(for: board))
                            .font(.system(size: caption2Size * scale, weight: .medium))
                            .foregroundStyle(typeColor)

                        if isAnchor {
                            Spacer(minLength: 0)
                            Image(systemSymbol: .pinFill)
                                .font(.system(size: caption2Size * scale))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(board.displayName)
                        .font(.system(size: captionSize * scale, weight: .semibold))
                        .lineLimit(2)

                    Text(detailText)
                        .font(.system(size: caption2Size * scale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Capsule()
                        .fill(.secondary.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .frame(height: DenOverviewLayout.widthIndicatorHeight * scale)
                }
                .padding(DenOverviewLayout.boardPadding * scale)
            }
        }
        .frame(
            width: cardWidth,
            height: DenOverviewLayout.boardCardHeight * scale,
            alignment: .leading
        )
        .foregroundStyle(.primary)
        .background(
            backgroundColor,
            in: RoundedRectangle(cornerRadius: DenRadius.small * scale, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: DenRadius.small * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.small * scale, style: .continuous)
                .stroke(
                    isSelected
                        ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.86))
                        : Color.primary.opacity(0.12),
                    lineWidth: (isSelected ? 2 : 1) * scale)
        }
    }
}
