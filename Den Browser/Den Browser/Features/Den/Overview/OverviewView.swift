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
                    .font(.title3.bold())

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
                .frame(width: DenOverviewLayout.searchFieldWidth)
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
                    .font(.caption.weight(.semibold))

                if desk.id == store.overviewSelectionDeskID {
                    Circle()
                        .fill(profileColor)
                        .frame(
                            width: DenOverviewLayout.selectionIndicatorSize,
                            height: DenOverviewLayout.selectionIndicatorSize)
                }
            }
            .foregroundStyle(Color.primary.opacity(desk.id == store.overviewSelectionDeskID ? 0.96 : 0.58))

            HStack(alignment: .top, spacing: 10) {
                if filteredBoards.isEmpty {
                    Text("Empty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(
                            width: DenOverviewLayout.emptyBoardSize.width,
                            height: DenOverviewLayout.emptyBoardSize.height
                        )
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
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)

                Text(
                    board.currentSheetURL?.host(percentEncoded: false)
                        ?? board.currentSheetURL?.absoluteString ?? ""
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Capsule()
                        .fill(.secondary.opacity(0.35))
                        .frame(
                            width: min(
                                max(
                                    board.width / DenOverviewLayout.widthIndicatorScale,
                                    DenOverviewLayout.widthIndicatorRange.lowerBound),
                                DenOverviewLayout.widthIndicatorRange.upperBound),
                            height: DenOverviewLayout.widthIndicatorHeight)
                }
            }
            .padding(DenOverviewLayout.boardPadding)
            .frame(
                width: DenOverviewLayout.boardSize.width,
                height: DenOverviewLayout.boardSize.height,
                alignment: .leading
            )
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

private enum DenOverviewLayout {
    static let contentPadding: CGFloat = 18
    static let closeButtonInset: CGFloat = 14
    static let searchFieldWidth: CGFloat = 320
    static let selectionIndicatorSize: CGFloat = 6
    static let emptyBoardSize = CGSize(width: 150, height: 88)
    static let boardSize = CGSize(width: 158, height: 96)
    static let boardPadding: CGFloat = 10
    static let widthIndicatorRange: ClosedRange<CGFloat> = 24...92
    static let widthIndicatorHeight: CGFloat = 5
    static let widthIndicatorScale: CGFloat = 9
}
