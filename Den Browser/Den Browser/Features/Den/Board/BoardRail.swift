import SFSafeSymbols
import SwiftUI

struct BoardRail: View {
    let profileColor: Color

    @Environment(DenStore.self) private var store

    private var railDesk: DeskState? {
        if store.isOverviewPresented,
            let selectedDeskID = store.overviewSelectionDeskID,
            let desk = store.state.desks.first(where: { $0.id == selectedDeskID })
        {
            return desk
        }
        return store.focusedDesk
    }

    private var boardSelection: Binding<UUID?> {
        Binding(
            get: {
                store.isOverviewPresented
                    ? store.overviewSelectionBoardID
                    : store.focusedDesk?.focusedBoardID
            },
            set: { boardID in
                guard let boardID else { return }
                if store.isOverviewPresented {
                    store.selectBoardInOverview(boardID)
                } else {
                    store.focusBoard(boardID)
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

                Button(action: openBoardAtEnd) {
                    Image(systemSymbol: .plus)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Board at End of Desk")
                .help("Open Board at End of Desk")
            }
            .listStyle(.sidebar)
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
                Text(store.isOverviewPresented ? "Overview Selection" : (railDesk?.label ?? "No Desk"))
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
        if store.isOverviewPresented {
            store.enterOverviewDesk(desk.id)
        }
        store.showOpenBoardPanel(afterBoardID: desk.boards.last?.id)
    }

    private func boardRow(_ board: BoardState) -> some View {
        let unreadNotificationCount = store.unreadNotificationCount(for: board.id)
        let isFocused = !store.isOverviewPresented && board.id == railDesk?.focusedBoardID
        let isOverviewSelected =
            store.isOverviewPresented
            && board.id == store.overviewSelectionBoardID
            && railDesk?.id == store.overviewSelectionDeskID
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
        .accessibilityIdentifier("board-rail-board.\(board.id.uuidString.lowercased())")
        .help(board.displayName)
    }

    @ViewBuilder
    private func boardIcon(for board: BoardState) -> some View {
        if board.isZmx {
            ZmxIcon(size: 16)
                .foregroundStyle(.secondary)
        } else if board.isTerminal {
            Image(systemSymbol: symbol(for: board))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        } else if let runtime = store.runtimes[board.id] {
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

    private func symbol(for board: BoardState) -> SFSymbol {
        board.isZellij
            ? .rectangle3Group
            : .appleTerminal
    }
}

private struct BoardRailFavicon: View {
    @ObservedObject var runtime: BoardRuntime

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
