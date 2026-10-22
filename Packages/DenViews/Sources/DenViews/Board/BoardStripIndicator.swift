import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

public struct BoardStripIndicator: View {
    private static let dotHeight: CGFloat = 6
    private static let sideDotHeight: CGFloat = 4
    private static let groupSpacing: CGFloat = 8
    private static let sideSpacing: CGFloat = 4

    let profileColor: Color

    @Environment(DenWindowModel.self) private var windowModel
    @Environment(AppearanceModel.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(profileColor: Color) { self.profileColor = profileColor }

    public var body: some View {
        if shouldShowBoardIndicator {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, DenLayout.outerInset)
                .allowsHitTesting(windowModel.temporaryContext == nil)
                .accessibilityHidden(windowModel.temporaryContext != nil)
                .transition(.opacity)
        }
    }

    private var shouldShowBoardIndicator: Bool {
        !windowModel.isZenViewPresented
            && windowModel.temporaryContext == nil
            && (windowModel.focusedDesk?.boards.count ?? 0) > 1
    }

    private var content: some View {
        let deskFilter = windowModel.deskFilter
        let boards =
            deskFilter.isPresented
            ? deskFilter.filteredBoards
            : windowModel.focusedDesk?.boards ?? []
        let focusedBoardID =
            deskFilter.isPresented
            ? deskFilter.selectionBoardID
            : windowModel.focusedDesk?.focusedBoardID
        let anchorBoardID = windowModel.focusedDesk?.anchorBoardID

        return HStack(spacing: 0) {
            ForEach(Array(boards.enumerated()), id: \.element.id) { index, board in
                let isFocused = board.id == focusedBoardID
                let isAnchor = board.id == anchorBoardID
                let isAttachedSide =
                    index > 0 && board.sideBoardTargetBoardID == boards[index - 1].id
                let dotSize = board.isSideBoard ? Self.sideDotHeight : Self.dotHeight
                let leadingGap: CGFloat =
                    index == 0 ? 0 : (isAttachedSide ? Self.sideSpacing : Self.groupSpacing)
                Button {
                    windowModel.focusBoard(board.id)
                } label: {
                    Capsule()
                        .fill(
                            isAnchor
                                ? profileColor.opacity(isFocused ? 1 : 0.72)
                                : Color.primary.opacity(isFocused ? 1 : (board.isSideBoard ? 0.22 : 0.28))
                        )
                        .frame(width: isFocused ? (board.isSideBoard ? 14 : 18) : dotSize, height: dotSize)
                        .frame(height: Self.dotHeight)
                        .padding(.horizontal, isAttachedSide ? 1 : 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, leadingGap)
                .help(board.isSideBoard ? "\(board.displayName) (Side Board)" : board.displayName)
                .accessibilityLabel(
                    [
                        "\(board.displayName) Board",
                        board.isSideBoard ? "Side Board" : nil,
                        isAnchor ? "Anchor Board" : nil,
                    ]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                )
            }
        }
        .frame(height: Self.dotHeight)
        .animation(DenMotion.spatial(reduceMotion: reduceMotion), value: focusedBoardID)
        .animation(DenMotion.spatial(reduceMotion: reduceMotion), value: boards.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-strip-indicator")
    }

    private var reduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}
