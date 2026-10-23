public import DenDomain
public import DenModels
import SFSafeSymbols
public import SwiftUI

public struct BoardRail<Favicon: View>: View {
    let profileColor: Color

    private let boardModel: (BoardState) -> BoardSurfaceModel
    private let focusBoard: (BoardID) -> Void
    private let reorderBoard: (BoardID, BoardIndex, DeskID, Bool) -> Void
    private let toggleAnchor: (BoardID, DeskID) -> Void
    private let favicon: (BoardID) -> Favicon
    @Environment(DenWindowModel.self) private var windowModel
    @FocusState private var isRailFocused: Bool

    private var railDesk: DeskState? {
        if windowModel.isOverviewPresented,
            let selectedDeskID = windowModel.overview.selectionDeskID,
            let desk = windowModel.desks.desks.first(where: { $0.id == selectedDeskID })
        {
            return desk
        }
        return windowModel.desks.focusedDesk
    }

    private var boardSelection: Binding<BoardID?> {
        Binding(
            get: {
                windowModel.isOverviewPresented
                    ? windowModel.overview.selectionBoardID
                    : windowModel.desks.focusedDesk?.focusedBoardID
            },
            set: { boardID in
                guard let boardID else { return }
                if windowModel.isOverviewPresented {
                    windowModel.overview.selectBoard(boardID)
                } else {
                    focusBoard(boardID)
                }
            }
        )
    }

    public init(
        profileColor: Color, boardModel: @escaping (BoardState) -> BoardSurfaceModel,
        focusBoard: @escaping (BoardID) -> Void, reorderBoard: @escaping (BoardID, BoardIndex, DeskID, Bool) -> Void,
        toggleAnchor: @escaping (BoardID, DeskID) -> Void, @ViewBuilder favicon: @escaping (BoardID) -> Favicon
    ) {
        self.profileColor = profileColor
        self.boardModel = boardModel
        self.focusBoard = focusBoard
        self.reorderBoard = reorderBoard
        self.toggleAnchor = toggleAnchor
        self.favicon = favicon
    }

    public var body: some View {
        VStack(spacing: 0) {
            railHeader

            List(selection: boardSelection) {
                ForEach(railDesk?.boards ?? []) { board in
                    boardRow(board)
                }
                .onMove(perform: moveBoards)

                Button(action: openBoardAtEnd) {
                    Image(systemSymbol: .plus)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Board at End of Desk")
                .help("Open Board at End of Desk")
            }
            .listStyle(.sidebar)
            .focused($isRailFocused)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("board-rail")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(DenLayout.outerInset)
        .background {
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .fill(Color.primary.opacity(0.035))
                .padding(8)
        }
    }

    private var railHeader: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .rectangleStack)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Boards")
                    .font(.headline)
                Text(windowModel.isOverviewPresented ? "Overview Selection" : (railDesk?.label ?? "No Desk"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DenLayout.chromeHorizontalPadding)
        .padding(.vertical, DenLayout.chromeHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openBoardAtEnd() {
        guard let desk = railDesk else { return }
        if windowModel.isOverviewPresented {
            windowModel.overview.enterDesk(desk.id)
        }
        windowModel.showOpenBoardPanel(afterBoardID: desk.boards.last?.id)
    }

    private func boardRow(_ board: BoardState) -> some View {
        let unreadNotificationCount = windowModel.notificationList.unreadCount(for: board.id)
        let isFocused = !windowModel.isOverviewPresented && board.id == railDesk?.focusedBoardID
        let isOverviewSelected =
            windowModel.isOverviewPresented
            && board.id == windowModel.overview.selectionBoardID
            && railDesk?.id == windowModel.overview.selectionDeskID
        let isAnchor = railDesk?.anchorBoardID == board.id

        return HStack(spacing: 8) {
            if board.isSideBoard {
                Image(systemSymbol: .arrowTurnDownRight)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 16)
                    .accessibilityHidden(true)
            }

            boardIcon(for: board)

            BoardHeaderTitle(
                board: board,
                isFocused: isFocused,
                isAnchor: isAnchor
            )

            if unreadNotificationCount > 0 {
                Circle()
                    .fill(profileColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        // On macOS 27.0.1, native sidebar selection stayed blue despite the Profile tint.
        // Hide this background while the Rail has focus to avoid blending with native selection.
        .listRowBackground(
            (isFocused || isOverviewSelected) && !isRailFocused
                ? RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
                    .fill(profileColor.opacity(DenSurfaceColors.selectionOpacity))
                    .padding(.horizontal, 10)
                : nil
        )
        .tag(board.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            boardAccessibilityLabel(
                board,
                isFocused: isFocused,
                isAnchor: isAnchor,
                isOverviewSelected: isOverviewSelected,
                unreadNotificationCount: unreadNotificationCount
            )
        )
        .accessibilityAddTraits(isFocused || isOverviewSelected ? .isSelected : [])
        .accessibilityAction(named: "Move Board Up") {
            moveBoardByDelta(board.id, delta: -1)
        }
        .accessibilityAction(named: "Move Board Down") {
            moveBoardByDelta(board.id, delta: 1)
        }
        .accessibilityIdentifier("board-rail-board.\(board.id.rawValue.uuidString.lowercased())")
        .help(board.displayName)
        .contextMenu {
            if let desk = railDesk {
                boardContextMenu(board, in: desk)
            }
        }
    }

    private func moveBoards(from sourceIndices: IndexSet, to destinationIndex: Int) {
        guard let desk = railDesk,
            let sourceIndex = sourceIndices.first,
            desk.boards.indices.contains(sourceIndex)
        else { return }

        let targetOffset = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        guard desk.boards.indices.contains(targetOffset), sourceIndex != targetOffset else { return }

        let board = desk.boards[sourceIndex]
        reorderBoard(board.id, BoardIndex(rawValue: targetOffset), desk.id, windowModel.isOverviewPresented)
        if windowModel.isOverviewPresented { windowModel.overview.selectBoard(board.id) }
    }

    private func moveBoardByDelta(_ boardID: BoardID, delta: Int) {
        guard let desk = railDesk,
            let currentIndex = desk.boards.firstIndex(where: { $0.id == boardID })
        else { return }
        let targetIndex = currentIndex + delta
        guard desk.boards.indices.contains(targetIndex) else { return }

        reorderBoard(boardID, BoardIndex(rawValue: targetIndex), desk.id, windowModel.isOverviewPresented)
        if windowModel.isOverviewPresented { windowModel.overview.selectBoard(boardID) }
    }

    @ViewBuilder
    private func boardContextMenu(_ board: BoardState, in desk: DeskState) -> some View {
        Button {
            toggleAnchor(board.id, desk.id)
        } label: {
            Label(
                desk.anchorBoardID == board.id ? "Clear Anchor Board" : "Set Anchor Board",
                systemSymbol: .pinFill
            )
        }

        Divider()

        Button {
            boardModel(board).perform(.focus)
            windowModel.showRenameBoardPanel()
        } label: {
            Label("Rename Board", systemSymbol: .pencil)
        }

        Button {
            boardModel(board).perform(.focus)
            boardModel(board).perform(.duplicate)
        } label: {
            Label("Duplicate Board", systemSymbol: .plusSquareOnSquare)
        }
        .disabled(board.isSideBoard)

        if windowModel.desks.desks.count > 1 {
            Menu {
                ForEach(Array(windowModel.desks.desks.enumerated()), id: \.element.id) { entry in
                    if entry.element.id != desk.id {
                        Button("\(entry.offset + 1). \(entry.element.label)") {
                            boardModel(board).perform(.focus)
                            boardModel(board).perform(.moveToDesk(entry.offset + 1))
                        }
                    }
                }
            } label: {
                Label("Move to Desk", systemSymbol: .rectangleStack)
            }
        }

        if board.isWeb {
            Button {
                boardModel(board).perform(.copyLocation)
            } label: {
                Label("Copy Current Sheet URL", systemSymbol: .documentOnDocument)
            }
            .disabled(board.currentSheetURL == nil && board.firstSheetURL == nil)
        }

        Divider()

        Button(role: .destructive) {
            boardModel(board).perform(.remove)
        } label: {
            Label("Remove Board", systemSymbol: .xmark)
        }
    }

    @ViewBuilder
    private func boardIcon(for board: BoardState) -> some View {
        if board.isTutorial || board.isTerminal || board.isInspection {
            Image(systemSymbol: boardSymbol(for: board.kind))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        } else {
            favicon(board.id)
        }
    }

    private func boardAccessibilityLabel(
        _ board: BoardState,
        isFocused: Bool,
        isAnchor: Bool,
        isOverviewSelected: Bool,
        unreadNotificationCount: Int
    ) -> String {
        let supplementaryText =
            board.currentSheetURL?.absoluteString
            ?? board.zellijSessionName
            ?? board.zmxSessionName
        return [
            board.isSideBoard ? "Side Board" : nil,
            isAnchor ? "Anchor Board" : nil,
            "Board: \(board.displayName)",
            supplementaryText,
            unreadNotificationCount > 0 ? "\(unreadNotificationCount) unread notifications" : nil,
            isFocused ? "Focused Board" : nil,
            isOverviewSelected ? "Overview Selection" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

public struct BoardRailFavicon: View {
    private let url: URL?
    public init(url: URL?) { self.url = url }

    public var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemSymbol: .globe)
                .foregroundStyle(.secondary)
        }
        .frame(width: 16, height: 16)
    }
}
