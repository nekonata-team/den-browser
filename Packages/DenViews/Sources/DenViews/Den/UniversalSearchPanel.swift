import AppKit
import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

public struct UniversalSearchPanel: View {
    let profileColor: Color

    @Environment(DenWindowModel.self) private var windowModel
    @FocusState private var isFocused: Bool

    private var search: UniversalSearchModel { windowModel.universalSearch }
    private let sourceItems: [UniversalSearchItem]
    private let recentItems: [RecentItem]
    private let boards: [BoardState]
    private let perform: (UniversalSearchItem.Target, Bool) -> String?
    private let restoreInput: () -> Void

    public init(
        profileColor: Color, sourceItems: [UniversalSearchItem], recentItems: [RecentItem],
        boards: [BoardState], perform: @escaping (UniversalSearchItem.Target, Bool) -> String?,
        restoreInput: @escaping () -> Void
    ) {
        self.profileColor = profileColor
        self.sourceItems = sourceItems
        self.recentItems = recentItems
        self.boards = boards
        self.perform = perform
        self.restoreInput = restoreInput
    }

    public var body: some View {
        @Bindable var search = search
        let results = search.results
        let selectedID = results.first(where: { $0.id == search.selectedID })?.id ?? results.first?.id
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: search.commandsOnly ? .chevronRight : .magnifyingglass) {
                TextField("Search Boards, Desks, Profiles, Essentials, Recent, or > commands", text: $search.query)
                    .denPanelHeaderField()
                    .focused($isFocused)
                    .accessibilityIdentifier("universal-search-input")
                    .onSubmit { TextInputComposition.performUnlessActive { submit() } }
            }

            if let message = search.message { DenValidationMessage(message) }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(results) { item in
                            Button {
                                submit(item, inDrawer: NSEvent.modifierFlags.contains(.option))
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemSymbol: symbol(for: item.target))
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title).font(.body).lineLimit(1)
                                        Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemSymbol: actionSymbol(for: item.target))
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                        .accessibilityHidden(true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .denSelectionHighlight(selectedID == item.id, profileColor: profileColor)
                            .id(item.id)
                        }
                    }
                }
                .frame(maxHeight: DenPanelLayout.standardListMaxHeight)
                .onChange(of: selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }

            if results.isEmpty {
                Text(search.commandsOnly ? "No matching commands" : "Search to find or create a Board")
                    .foregroundStyle(.secondary)
            }
            DenPanelHint("↑↓ Select · Return Run · ⌥Return / ⌥Click Drawer · Escape Close · > Commands")
        }
        .denPanel(width: DenPanelLayout.wideWidth)
        .onChange(of: recentItems.map { [$0.displayText, $0.title ?? ""] }, initial: true) { _, _ in
            search.recentItems = recentItems
        }
        .onChange(of: sourceItems, initial: true) { _, items in search.items = items }
        .onChange(of: search.query) { _, value in
            search.message = nil
            if isFocused { TextInputComposition.syncActiveFieldEditor(to: value) }
        }
        .onChange(of: search.submissionRequest) { _, _ in submit(inDrawer: search.submitsInDrawer) }
        .onAppear { DispatchQueue.main.async { isFocused = true } }
        .onExitCommand {
            windowModel.hideUniversalSearch()
            restoreInput()
        }
    }

    private func actionSymbol(for target: UniversalSearchItem.Target) -> SFSymbol {
        switch target {
        case .board, .desk, .profile: .arrowRight
        case .essential, .recent, .createBoard: .plusApp
        case .command: .chevronRight
        }
    }

    private func symbol(for target: UniversalSearchItem.Target) -> SFSymbol {
        switch target {
        case .board(let id):
            boards.first(where: { $0.id == id }).map { boardSymbol(for: $0.kind) } ?? .rectangle
        case .desk: .rectangleStack
        case .profile: .personFill
        case .essential: .sparkles
        case .recent: .clock
        case .createBoard: .plusRectangleOnRectangle
        case .command(let command):
            switch command {
            case .newDesk: .plusRectangleOnRectangle
            case .openProfile: .personFill
            case .openSettings: .gearshape
            case .toggleZenView: .rectangle
            case .toggleFocusMode: .eye
            case .restoreBoard: .arrowCounterclockwise
            }
        }
    }

    private func submit(_ item: UniversalSearchItem? = nil, inDrawer: Bool = false) {
        guard let item = item ?? search.selectedItem else { return }
        search.message = perform(item.target, inDrawer)
    }
}
