import DenDesign
import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

struct BoardRail: View {
    let profileColor: Color

    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel
    @FocusState private var isRailFocused: Bool

    private var railDesk: DeskState? {
        if windowModel.isOverviewPresented,
            let selectedDeskID = windowModel.overview.selectionDeskID,
            let desk = controller.state.desks.first(where: { $0.id == selectedDeskID })
        {
            return desk
        }
        return controller.focusedDesk
    }

    private var boardSelection: Binding<BoardID?> {
        Binding(
            get: {
                windowModel.isOverviewPresented
                    ? windowModel.overview.selectionBoardID
                    : controller.focusedDesk?.focusedBoardID
            },
            set: { boardID in
                guard let boardID else { return }
                if windowModel.isOverviewPresented {
                    windowModel.overview.selectBoard(boardID)
                } else {
                    controller.focusBoard(boardID)
                }
            }
        )
    }

    var body: some View {
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
        let unreadNotificationCount = controller.unreadNotificationCount(for: board.id)
        let isFocused = !windowModel.isOverviewPresented && board.id == railDesk?.focusedBoardID
        let isOverviewSelected =
            windowModel.isOverviewPresented
            && board.id == windowModel.overview.selectionBoardID
            && railDesk?.id == windowModel.overview.selectionDeskID
        let isAnchor = railDesk?.anchorBoardID == board.id

        return HStack(spacing: 8) {
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
        if windowModel.isOverviewPresented {
            controller.reorderBoardGroup(
                containing: board.id,
                to: BoardIndex(rawValue: targetOffset),
                in: DeskIndex(rawValue: controller.state.desks.firstIndex(where: { $0.id == desk.id }) ?? 0)
            )
            controller.save()
            windowModel.overview.selectBoard(board.id)
        } else {
            controller.focusBoard(board.id)
            controller.previewBoardMove(board.id, to: BoardIndex(rawValue: targetOffset))
            controller.save()
        }
    }

    private func moveBoardByDelta(_ boardID: BoardID, delta: Int) {
        guard let desk = railDesk,
            let currentIndex = desk.boards.firstIndex(where: { $0.id == boardID })
        else { return }
        let targetIndex = currentIndex + delta
        guard desk.boards.indices.contains(targetIndex) else { return }

        if windowModel.isOverviewPresented {
            controller.reorderBoardGroup(
                containing: boardID,
                to: BoardIndex(rawValue: targetIndex),
                in: DeskIndex(rawValue: controller.state.desks.firstIndex(where: { $0.id == desk.id }) ?? 0)
            )
            controller.save()
            windowModel.overview.selectBoard(boardID)
        } else {
            controller.focusBoard(boardID)
            controller.previewBoardMove(boardID, to: BoardIndex(rawValue: targetIndex))
            controller.save()
        }
    }

    @ViewBuilder
    private func boardContextMenu(_ board: BoardState, in desk: DeskState) -> some View {
        Button {
            controller.toggleAnchorBoard(board.id, in: desk.id)
        } label: {
            Label(
                desk.anchorBoardID == board.id ? "Clear Anchor Board" : "Set Anchor Board",
                systemSymbol: .pinFill
            )
        }

        Divider()

        Button {
            controller.focusBoard(board.id)
            windowModel.showRenameBoardPanel()
        } label: {
            Label("Rename Board", systemSymbol: .pencil)
        }

        Button {
            controller.focusBoard(board.id)
            controller.duplicateFocusedBoard()
        } label: {
            Label("Duplicate Board", systemSymbol: .plusSquareOnSquare)
        }
        .disabled(board.isSideBoard)

        if controller.state.desks.count > 1 {
            Menu {
                ForEach(Array(controller.state.desks.enumerated()), id: \.element.id) { entry in
                    if entry.element.id != desk.id {
                        Button("\(entry.offset + 1). \(entry.element.label)") {
                            controller.focusBoard(board.id)
                            controller.moveFocusedBoard(toDeskNumber: entry.offset + 1)
                        }
                    }
                }
            } label: {
                Label("Move to Desk", systemSymbol: .rectangleStack)
            }
        }

        if board.isWeb {
            Button {
                controller.copyBoardLocation(board.id)
            } label: {
                Label("Copy Current Sheet URL", systemSymbol: .documentOnDocument)
            }
            .disabled(board.currentSheetURL == nil && board.firstSheetURL == nil)
        }

        Divider()

        Button(role: .destructive) {
            controller.removeBoard(board.id)
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
        } else if let runtime = controller.webRuntimes[board.id] {
            BoardRailFavicon(runtime: runtime)
        } else {
            Image(systemSymbol: .globe)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
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

private struct BoardRailFavicon: View {
    @ObservedObject var runtime: WebRuntime

    var body: some View {
        AsyncImage(url: runtime.faviconURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemSymbol: .globe)
                .foregroundStyle(.secondary)
        }
        .frame(width: 16, height: 16)
    }
}
