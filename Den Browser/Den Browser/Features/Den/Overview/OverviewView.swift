import SwiftUI

struct OverviewView: View {
    let profileColor: Color

    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @FocusState private var isSearchFocused: Bool
    @State private var scrollPosition = ScrollPosition()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 12) {
                Text("Overview")
                    .font(.system(size: 20, weight: .bold))

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(store.isOverviewFilterMode ? .primary : .secondary)

                    TextField(
                        "Search desks and boards (/)",
                        text: Binding(
                            get: { store.overviewQuery },
                            set: { store.setOverviewQuery($0) }
                        )
                    )
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .disabled(!store.isOverviewFilterMode)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 320)
                .background(
                    Color.primary.opacity(store.isOverviewFilterMode ? 0.08 : 0.04),
                    in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                        .stroke(
                            store.isOverviewFilterMode ? profileColor.opacity(0.86) : Color.primary.opacity(0.10),
                            lineWidth: store.isOverviewFilterMode ? 1.5 : 1
                        )
                }
                .onTapGesture {
                    if !store.isOverviewFilterMode {
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
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                store.hideOverview()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glass)
            .padding(14)
        }
        .onExitCommand {
            store.hideOverview()
        }
        .onChange(of: store.isOverviewFilterMode) { _, newValue in
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

    private func deskRow(_ desk: DeskState, filteredBoards: [BoardState]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(desk.label)
                    .font(.system(size: 13, weight: .semibold))

                if desk.id == store.overviewSelectionDeskID {
                    Circle()
                        .fill(profileColor)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(Color.primary.opacity(desk.id == store.overviewSelectionDeskID ? 0.96 : 0.58))

            HStack(alignment: .top, spacing: 10) {
                if filteredBoards.isEmpty {
                    Text("Empty")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 150, height: 88)
                        .background(
                            Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous))
                } else {
                    ForEach(filteredBoards) { board in
                        overviewBoard(board, in: desk)
                    }
                }
            }
        }
    }

    private func overviewBoard(_ board: BoardState, in desk: DeskState) -> some View {
        let isSelected = desk.id == store.overviewSelectionDeskID && board.id == store.overviewSelectionBoardID
        return Button {
            store.selectBoardInOverview(board.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(board.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)

                Text(
                    board.currentSheetURL?.host(percentEncoded: false)
                        ?? board.currentSheetURL?.absoluteString ?? ""
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Capsule()
                        .fill(.secondary.opacity(0.35))
                        .frame(width: max(24, min(92, board.width / 9)), height: 5)
                }
            }
            .padding(10)
            .frame(width: 158, height: 96, alignment: .leading)
            .foregroundStyle(.primary)
            .background(
                Color.primary.opacity(isSelected ? 0.18 : 0.09),
                in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                    .stroke(
                        isSelected ? profileColor.opacity(0.86) : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .id(board.id)
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}
