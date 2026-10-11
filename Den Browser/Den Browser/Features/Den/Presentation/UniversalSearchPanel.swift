import DenDesign
import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

struct UniversalSearchPanel: View {
    let profileName: String
    let profileColor: Color

    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.openSettings) private var openSettings
    @FocusState private var isFocused: Bool

    private var search: UniversalSearchModel { windowModel.universalSearch }
    private var sourceItems: [UniversalSearchItem] {
        UniversalSearchActions.items(
            controller: controller, profiles: profileManager.profiles, profileName: profileName)
    }

    var body: some View {
        @Bindable var search = search
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: search.commandsOnly ? .chevronRight : .magnifyingglass) {
                TextField("Search Boards, Desks, Profiles, Essentials, or > commands", text: $search.query)
                    .denPanelHeaderField()
                    .focused($isFocused)
                    .accessibilityIdentifier("universal-search-input")
                    .onSubmit { TextInputComposition.performUnlessActive { submit() } }
            }

            if let message = search.message { DenValidationMessage(message) }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(search.results) { item in
                            Button {
                                submit(item)
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
                            .denSelectionHighlight(search.selectedItem?.id == item.id, profileColor: profileColor)
                            .id(item.id)
                        }
                    }
                }
                .frame(maxHeight: 360)
                .onChange(of: search.selectedItem?.id) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }

            if search.results.isEmpty {
                Text("No matching commands").foregroundStyle(.secondary)
            }
            DenPanelHint("↑↓ Select · Return Run · Escape Close · > Commands")
        }
        .denPanel(width: 600)
        .onChange(of: sourceItems, initial: true) { _, items in search.items = items }
        .onChange(of: search.query) { _, value in
            search.message = nil
            if isFocused { TextInputComposition.syncActiveFieldEditor(to: value) }
        }
        .onChange(of: search.submissionRequest) { _, _ in submit() }
        .onAppear { DispatchQueue.main.async { isFocused = true } }
        .onExitCommand {
            windowModel.hideUniversalSearch()
            controller.restoreFocusedFirstResponder()
        }
    }

    private func actionSymbol(for target: UniversalSearchItem.Target) -> SFSymbol {
        switch target {
        case .board, .desk, .profile: .arrowRight
        case .essential, .createBoard: .plusApp
        case .command: .chevronRight
        }
    }

    private func symbol(for target: UniversalSearchItem.Target) -> SFSymbol {
        switch target {
        case .board(let id):
            controller.board(for: id).map { boardSymbol(for: $0.kind) } ?? .rectangle
        case .desk: .rectangleStack
        case .profile: .personFill
        case .essential: .sparkles
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

    private func submit(_ item: UniversalSearchItem? = nil) {
        guard let item = item ?? search.selectedItem else { return }
        search.message = UniversalSearchActions.perform(
            item.target, controller: controller, windowModel: windowModel,
            openProfile: { id in
                profileManager.profile(id: id) != nil && profileManager.openWindow(for: id)
            }, openSettings: { openSettings() })
    }
}
