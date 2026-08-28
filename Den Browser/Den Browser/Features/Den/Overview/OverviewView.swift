import SwiftUI

struct OverviewView: View {
    let profileColor: Color
    let boardHeight: CGFloat

    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.appearsActive) private var appearsActive

    @FocusState private var isSearchFocused: Bool
    @State private var scrollPosition = ScrollPosition()
    @State private var overviewDrag: OverviewDragState?
    @State private var overviewGeometry = OverviewGeometry()
    @State private var scrollSize = CGSize.zero
    @State private var lastAutoScrollTime = 0.0
    @State private var hoveredBoardID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 12) {
                Text("Overview")
                    .font(.title3.bold())

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(store.isOverviewFilterInputActive ? .primary : .secondary)
                        .accessibilityHidden(true)

                    TextField(
                        text: Binding(
                            get: { store.overviewQuery },
                            set: { store.setOverviewQuery($0) }
                        ),
                        prompt: Text("Search desks and boards")
                    ) {
                        Text("Search desks and boards")
                    }
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .disabled(!store.isOverviewFilterInputActive)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: DenOverviewLayout.searchFieldWidth)
                .background(
                    Color.primary.opacity(store.isOverviewFilterInputActive ? 0.08 : 0.04),
                    in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                        .stroke(
                            store.isOverviewFilterInputActive
                                ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.86))
                                : Color.primary.opacity(0.10),
                            lineWidth: store.isOverviewFilterInputActive ? 1.5 : 1
                        )
                }
                .onTapGesture {
                    if !store.isOverviewFilterInputActive {
                        store.enterOverviewFilterMode()
                    }
                }
            }
            .frame(maxWidth: .infinity)

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(store.state.desks) { desk in
                        let filtered = desk.boards.filter { board in
                            store.matchesOverviewFilter(board, in: desk)
                        }
                        if store.overviewQuery.isEmpty {
                            deskRow(desk, filteredBoards: filtered)
                        } else if !filtered.isEmpty {
                            deskRow(desk, filteredBoards: filtered)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(2)
                .animation(
                    DenMotion.spatial(reduceMotion: shouldReduceMotion),
                    value: store.state.desks.map { $0.boards.map(\.id) })
            }
            .scrollPosition($scrollPosition, anchor: .center)
            .coordinateSpace(name: OverviewCoordinateSpace.name)
            .onScrollGeometryChange(for: CGSize.self) { geometry in
                geometry.containerSize
            } action: { _, size in
                scrollSize = size
            }
            .onPreferenceChange(OverviewBoardFramePreferenceKey.self) {
                overviewGeometry.boardFrames = $0
            }
            .onPreferenceChange(OverviewDeskFramePreferenceKey.self) {
                overviewGeometry.deskFrames = $0
            }
            .onPreferenceChange(OverviewEmptyBoardFramePreferenceKey.self) {
                overviewGeometry.emptyBoardFrames = $0
            }
            .onChange(of: store.boardDragCancellationRequest) { _, _ in
                cancelOverviewBoardDrag()
            }
            .onChange(of: store.temporaryContext) { _, context in
                if context != .overview { cancelOverviewBoardDrag() }
            }
            .onChange(of: appearsActive) { _, isActive in
                if !isActive { cancelOverviewBoardDrag() }
            }
            .overlay(alignment: .topLeading) {
                if let drag = overviewDrag, let board = draggedOverviewBoard {
                    overviewBoardCard(board, isSelected: true)
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
                    ContentUnavailableView.search(text: store.overviewQuery)
                }
            }
        }
        .padding(DenOverviewLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .overlay(alignment: .topTrailing) {
            DenCloseButton(label: "Close Overview") {
                store.hideOverview()
            }
            .padding(DenOverviewLayout.closeButtonInset)
        }
        .onExitCommand {
            store.hideOverview()
        }
        .onChange(of: store.isOverviewFilterInputActive) { _, newValue in
            isSearchFocused = newValue
        }
        .onChange(of: store.overviewSelectionBoardID) { _, boardID in
            scrollToSelection(boardID)
        }
        .onAppear {
            scrollToSelection(store.overviewSelectionBoardID)
        }
    }

    private func scrollToSelection(_ boardID: UUID?) {
        guard let boardID else { return }
        withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
            scrollPosition.scrollTo(id: boardID, anchor: .center)
        }
    }

    private var hasOverviewMatches: Bool {
        store.overviewQuery.isEmpty
            || store.state.desks.contains { desk in
                desk.boards.contains { store.matchesOverviewFilter($0, in: desk) }
            }
    }

    private func deskRow(_ desk: DeskState, filteredBoards: [BoardState]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(desk.label)
                    .font(.caption.weight(.semibold))

                if desk.id == store.overviewSelectionDeskID {
                    Circle()
                        .fill(profileColor)
                        .frame(
                            width: DenOverviewLayout.selectionIndicatorSize,
                            height: DenOverviewLayout.selectionIndicatorSize
                        )
                        .overlay {
                            if differentiateWithoutColor {
                                Circle()
                                    .stroke(Color.primary, lineWidth: 1)
                            }
                        }
                }
            }
            .foregroundStyle(Color.primary.opacity(desk.id == store.overviewSelectionDeskID ? 0.96 : 0.58))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Desk \(desk.label)")
            .accessibilityValue(desk.id == store.overviewSelectionDeskID ? "Selected Desk" : "")
            .accessibilityAddTraits(desk.id == store.overviewSelectionDeskID ? .isSelected : [])

            HStack(alignment: .top, spacing: DenOverviewLayout.boardSpacing) {
                if filteredBoards.isEmpty {
                    emptyDeskCard(desk)
                } else {
                    ForEach(filteredBoards) { board in
                        overviewBoard(board, in: desk)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview-desk.\(desk.id.uuidString.lowercased())")
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
        let isSelected = desk.id == store.overviewSelectionDeskID && board.id == store.overviewSelectionBoardID
        return ZStack(alignment: .topTrailing) {
            Button {
                store.selectBoardInOverview(board.id)
            } label: {
                overviewBoardCard(board, isSelected: isSelected)
            }
            .buttonStyle(.plain)

            if hoveredBoardID == board.id && overviewDrag == nil {
                OverviewBoardCloseButton(boardName: board.displayName) {
                    store.removeBoard(board.id)
                }
                .padding(DenOverviewLayout.boardCloseButtonPadding)
            }
        }
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
                    value: [board.id: proxy.frame(in: .named(OverviewCoordinateSpace.name))])
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
        .accessibilityLabel(overviewBoardAccessibilityLabel(for: board))
        .accessibilityValue(isSelected ? "Selected Board" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("overview-board.\(board.id.uuidString.lowercased())")
        .accessibilityHint("Drag to move this Board, or use Board movement actions")
        .accessibilityAction(named: "Enter Board") {
            store.enterOverviewBoard(board.id)
        }
        .accessibilityAction(named: "Remove Board") {
            store.removeBoard(board.id)
        }
        .accessibilityAction(named: "Move Board Left") {
            store.selectBoardInOverview(board.id)
            store.moveOverviewSelectionBoardLeft()
        }
        .accessibilityAction(named: "Move Board Right") {
            store.selectBoardInOverview(board.id)
            store.moveOverviewSelectionBoardRight()
        }
        .accessibilityAction(named: "Move Board to Previous Desk") {
            store.selectBoardInOverview(board.id)
            store.moveOverviewSelectionBoardToPreviousDesk()
        }
        .accessibilityAction(named: "Move Board to Next Desk") {
            store.selectBoardInOverview(board.id)
            store.moveOverviewSelectionBoardToNextDesk()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                store.enterOverviewBoard(board.id)
            }
        )
        .id(board.id)
    }

    private func emptyDeskCard(_ desk: DeskState) -> some View {
        Button {
            store.selectDeskInOverview(desk.id)
        } label: {
            Text("Empty")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    width: DenOverviewLayout.emptyBoardWidth,
                    height: DenOverviewLayout.boardCardHeight
                )
                .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(
                        cornerRadius: DenRadius.medium,
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
            TapGesture(count: 2).onEnded {
                store.enterOverviewDesk(desk.id)
            })
    }

    private func overviewBoardAccessibilityLabel(for board: BoardState) -> String {
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

        return [overviewBoardKindLabel(for: board) + " Board \(board.displayName)", detail]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func overviewBoardCard(_ board: BoardState, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: overviewBoardSystemImage(for: board))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(overviewBoardTypeColor(for: board))
                    .accessibilityHidden(true)

                Text(overviewBoardKindLabel(for: board))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(overviewBoardTypeColor(for: board))
            }

            Text(board.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            Text(overviewBoardDetail(for: board))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(maxWidth: .infinity)
                .frame(height: DenOverviewLayout.widthIndicatorHeight)
        }
        .padding(DenOverviewLayout.boardPadding)
        .frame(
            width: overviewBoardCardWidth(for: board),
            height: DenOverviewLayout.boardCardHeight,
            alignment: .leading
        )
        .foregroundStyle(.primary)
        .background(
            overviewBoardBackground(for: board, isSelected: isSelected),
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .stroke(
                    isSelected
                        ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.86))
                        : Color.primary.opacity(0.12),
                    lineWidth: isSelected ? 2 : 1)
        }
    }

    private func overviewBoardCardWidth(for board: BoardState) -> CGFloat {
        CGFloat(board.width) * DenOverviewLayout.boardCardHeight / boardHeight
    }

    private func overviewBoardSystemImage(for board: BoardState) -> String {
        board.isTerminal ? "terminal" : "globe"
    }

    private func overviewBoardTypeColor(for board: BoardState) -> Color {
        board.isTerminal ? DenOverviewColors.terminal : DenOverviewColors.web
    }

    private func overviewBoardBackground(for board: BoardState, isSelected: Bool) -> Color {
        if isSelected { return profileColor.opacity(0.18) }
        return overviewBoardTypeColor(for: board).opacity(0.09)
    }

    private func overviewBoardKindLabel(for board: BoardState) -> String {
        if board.isZmx { return "zmx" }
        if board.isZellij { return "Zellij" }
        if board.isTerminal { return "Terminal" }
        return "Web"
    }

    private func overviewBoardDetail(for board: BoardState) -> String {
        board.zmxSessionName
            ?? board.zellijSessionName
            ?? board.terminalWorkingDirectory
            ?? board.currentSheetURL?.host(percentEncoded: false)
            ?? board.currentSheetURL?.absoluteString
            ?? ""
    }

    private func updateOverviewBoardDrag(_ board: BoardState, value: DragGesture.Value) {
        if overviewDrag == nil {
            guard
                let frame = overviewGeometry.boardFrames[board.id],
                store.beginOverviewBoardDrag(board.id)
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
            store.cancelOverviewBoardDrag()
            overviewDrag = nil
            return
        }
        store.finishOverviewBoardDrag(drag.boardID, toDeskID: target.deskID, at: target.index)
        overviewDrag = nil
    }

    private func cancelOverviewBoardDrag() {
        guard overviewDrag != nil else { return }
        store.cancelOverviewBoardDrag()
        overviewDrag = nil
    }

    private var overviewDropTarget: OverviewDropTarget? {
        guard
            let drag = overviewDrag,
            let target = overviewInsertionTarget(at: drag.location),
            let desk = store.state.desks.first(where: { $0.id == target.deskID })
        else {
            return nil
        }

        let orderedBoardIDs = desk.boards.map(\.id).filter { $0 != drag.boardID }
        if let referenceID = orderedBoardIDs.indices.contains(target.index)
            ? orderedBoardIDs[target.index]
            : orderedBoardIDs.last,
            let frame = overviewGeometry.boardFrames[referenceID]
        {
            let isBeforeReference = target.index < orderedBoardIDs.count
            return OverviewDropTarget(
                lineX: isBeforeReference
                    ? frame.minX - DenOverviewLayout.boardSpacing / 2
                    : frame.maxX + DenOverviewLayout.boardSpacing / 2,
                lineY: frame.midY,
                height: frame.height + 8)
        } else if let frame = overviewGeometry.emptyBoardFrames[desk.id] {
            return OverviewDropTarget(
                lineX: frame.minX - DenOverviewLayout.boardSpacing / 2,
                lineY: frame.midY,
                height: frame.height + 8)
        } else {
            return nil
        }
    }

    private func overviewInsertionTarget(at location: CGPoint) -> (deskID: UUID, index: Int)? {
        guard
            let drag = overviewDrag,
            scrollBounds.contains(location),
            let deskID = OverviewDragGeometry.targetDeskID(
                at: location,
                frames: overviewGeometry.deskFrames),
            let desk = store.state.desks.first(where: { $0.id == deskID }),
            let index = OverviewDragGeometry.targetIndex(
                draggedID: drag.boardID,
                orderedIDs: desk.boards.map(\.id),
                locationX: location.x,
                frames: overviewGeometry.boardFrames)
        else { return nil }
        return (deskID, index)
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
            let desk = store.state.desks.first(where: { $0.id == deskID }),
            let boardID = (isLeading ? desk.boards.first : desk.boards.last)?.id
        {
            withAnimation(.linear(duration: shouldReduceMotion ? 0 : 0.14)) {
                scrollPosition.scrollTo(id: boardID, anchor: .center)
            }
        } else if let deskID = nearestDeskID(to: location.y, leading: isLeading) {
            withAnimation(.linear(duration: shouldReduceMotion ? 0 : 0.14)) {
                scrollPosition.scrollTo(id: deskID, anchor: .center)
            }
        }
    }

    private func nearestDeskID(to locationY: CGFloat, leading: Bool) -> UUID? {
        let desks = store.state.desks
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
        return store.state.desks.lazy.compactMap { desk in
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
    static let contentPadding: CGFloat = 18
    static let closeButtonInset: CGFloat = 14
    static let searchFieldWidth: CGFloat = 320
    static let selectionIndicatorSize: CGFloat = 6
    static let emptyBoardWidth: CGFloat = 150
    static let boardCardHeight: CGFloat = 120
    static let boardSpacing: CGFloat = 10
    static let boardPadding: CGFloat = 10
    static let widthIndicatorHeight: CGFloat = 5
    static let boardCloseButtonSize: CGFloat = 18
    static let boardCloseButtonPadding: CGFloat = 6
}

private struct OverviewBoardCloseButton: View {
    let boardName: String
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .frame(
                    width: DenOverviewLayout.boardCloseButtonSize,
                    height: DenOverviewLayout.boardCloseButtonSize
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
}

private struct OverviewDragState {
    let boardID: UUID
    var location: CGPoint
    let pointerToCenter: CGSize

    var previewCenter: CGPoint {
        CGPoint(
            x: location.x + pointerToCenter.width,
            y: location.y + pointerToCenter.height)
    }
}

private struct OverviewGeometry {
    var boardFrames: [UUID: CGRect] = [:]
    var deskFrames: [UUID: CGRect] = [:]
    var emptyBoardFrames: [UUID: CGRect] = [:]
}

private struct OverviewDropTarget {
    let lineX: CGFloat
    let lineY: CGFloat
    let height: CGFloat
}

private enum OverviewCoordinateSpace {
    static let name = "overview"
}

private struct OverviewBoardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct OverviewDeskFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct OverviewEmptyBoardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
