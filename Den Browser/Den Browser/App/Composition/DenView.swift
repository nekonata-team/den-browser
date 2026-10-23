import DenApplication
import DenDomain
import DenModels
import DenViews
import SwiftUI

struct DenView<Header: View>: View {
    private let profileName: String?
    private let profileColor: Color
    private let isPrivateDen: Bool
    private let shouldShowHeader: Bool
    private let header: Header
    @Environment(ProfileWindowSession.self) private var session
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(AppPreferences.self) private var preferences

    init(
        profileName: String? = nil, profileColor: Color = .blue, isPrivateDen: Bool = false, shouldShowHeader: Bool,
        @ViewBuilder header: () -> Header
    ) {
        self.profileName = profileName
        self.profileColor = profileColor
        self.isPrivateDen = isPrivateDen
        self.shouldShowHeader = shouldShowHeader
        self.header = header()
    }
    var body: some View {
        DenViews.DenView(
            profileName: profileName, profileColor: profileColor, isPrivateDen: isPrivateDen,
            shouldShowHeader: shouldShowHeader, motionPreference: preferences.motionPreference,
            drawerStyle: preferences.drawerStyle, sheetScale: preferences.sheetScale,
            activities: windowModel.downloads.activities,
            onScaleChange: { session.runtimes.applySheetScale($0) },
            onMotionChange: { session.configuration.sheetNavigation.setReduceMotion($0) },
            onOpenTutorial: { session.boardOpening.openTutorialBoard(preferredWidth: $0) },
            header: { header }, rail: { BoardRail(profileColor: profileColor) },
            strip: { size in
                BoardStrip(
                    size: size, shouldShowHeader: false, profileColor: profileColor,
                    boardSpacing: DenLayout.outerInset, boardHorizontalPadding: DenLayout.outerInset,
                    onOpenBoardAtEnd: { windowModel.showOpenBoardPanel(afterBoardID: $0) })
            },
            panels: { size in
                DenActivePanelOverlay(
                    size: size, profileName: profileName, profileColor: profileColor, shouldShowHeader: shouldShowHeader
                )
            },
            drawer: { size in
                DenDrawerOverlay(size: size, profileColor: profileColor, shouldShowHeader: shouldShowHeader)
            }
        )
        .modifier(DenDialogs())
    }
}

extension DenView where Header == EmptyView {
    init(profileName: String? = nil, profileColor: Color = .blue) {
        self.init(profileName: profileName, profileColor: profileColor, shouldShowHeader: false) { EmptyView() }
    }
}

private struct DenDrawerOverlay: View {
    let size: CGSize
    let profileColor: Color
    let shouldShowHeader: Bool
    @Environment(ProfileWindowSession.self) private var session
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        DenViews.DenDrawerOverlay(
            size: size, profileColor: profileColor, shouldShowHeader: shouldShowHeader,
            drawerStyle: preferences.drawerStyle, motionPreference: preferences.motionPreference,
            peek: { item, isFocused in
                DrawerWebSurface(webView: session.drawer.drawerRuntime(for: item).webView, isFocused: isFocused)
            }, placeFromContextMenu: { _ = session.drawer.placeDrawerItemAsBoard($0) })
    }
}

private struct DenActivePanelOverlay: View {
    let size: CGSize
    let profileName: String?
    let profileColor: Color
    let shouldShowHeader: Bool
    @Environment(\.openSettings) private var openSettings
    @Environment(ProfileWindowSession.self) private var session
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(ProfileManager.self) private var profileManager
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        DenViews.DenActivePanelOverlay(
            size: size, shouldShowHeader: shouldShowHeader,
            motionPreference: preferences.motionPreference,
            restoreInput: session.runtimes.restoreFocusedFirstResponder
        ) { context, newBoardWidth, boardHeight in
            activePanel(context, newBoardWidth: newBoardWidth, boardHeight: boardHeight)
        }
    }

    @ViewBuilder
    private func activePanel(_ context: TemporaryContext, newBoardWidth: CGFloat, boardHeight: CGFloat) -> some View {
        switch context {
        case .universalSearch:
            UniversalSearchPanel(
                profileColor: profileColor,
                sourceItems: UniversalSearchModel.sourceItems(
                    state: session.resources.data.snapshot.den, essentials: preferences.essentials,
                    hasRemovedBoards: !session.resources.data.snapshot.recentlyRemovedBoards.isEmpty,
                    profiles: profileManager.profiles, profileName: profileName ?? ""),
                recentItems: session.resources.data.snapshot.recentItems,
                boards: session.resources.data.snapshot.den.desks.flatMap(\.boards),
                perform: { target, inDrawer in
                    UniversalSearchActions.perform(
                        target, session: session, windowModel: windowModel, inDrawer: inDrawer,
                        openProfile: { id in
                            profileManager.profile(id: id) != nil && profileManager.openWindow(for: id)
                        }, openSettings: { openSettings() })
                }, restoreInput: { session.runtimes.restoreFocusedFirstResponder() })
        case .essentialsPrefix:
            EssentialsPrefixPanel(
                profileColor: profileColor,
                essentials: session.configuration.preferences.essentials,
                selectedEssentialID: windowModel.selectedEssentialID,
                onSelect: { windowModel.selectEssential($0) },
                onOpenInDrawer: { windowModel.launchEssential(id: $0, inDrawer: true) }
            )
        case .openBoard:
            OpenBoardPanel(profileColor: profileColor, newBoardWidth: newBoardWidth)
        case .zmxSessions:
            ZmxSessionsPanel(profileColor: profileColor)
        case .zmxDuplication:
            ZmxDuplicationPanel()
        case .editBoardLink:
            EditBoardLinkPanel()
        case .newDesk, .replaceDesk:
            NewDeskPanel(profileColor: profileColor, boardHeight: boardHeight)
        case .deskPresetManagement:
            DeskPresetManagementPanel(
                isStandalone: true,
                profileColor: profileColor,
                presets: session.resources.data.snapshot.deskPresets,
                boardHeight: boardHeight,
                renamePreset: windowModel.deskPresetActions.rename,
                requestDeletion: windowModel.deskPresetActions.requestDeletion
            ) {
                windowModel.hideNewDeskPanel(exitsDenMode: true)
            }
        case .boardWidth:
            BoardWidthPanel()
        case .saveDeskPreset:
            SaveDeskPresetPanel(
                initialLabel: session.navigation.focusedDesk?.label ?? "",
                previewBoards: DeskPresetBoard.capture(from: session.navigation.focusedDesk?.boards ?? []),
                boardHeight: boardHeight,
                savePreset: windowModel.deskPresetActions.save,
                onClose: { windowModel.hideSaveDeskPresetPanel() }
            )
        case .renameBoard:
            RenameBoardPanel()
        case .renameDesk:
            RenameDeskPanel()
        case .saveEssential:
            SaveEssentialPanel()
        case .overview:
            OverviewView(profileColor: profileColor, boardHeight: boardHeight)
        case .boardActivity:
            BoardActivityView(
                profileColor: profileColor, resources: session.resources,
                remove: { session.boardRemoval.removeBoard($0) })
        case .keyboardShortcuts:
            KeyboardShortcutsView(onClose: windowModel.hideKeyboardShortcuts)
        case .profilePicker:
            OpenProfilePanel(
                profiles: profileManager.profiles,
                profileColor: profileColor,
                onOpenProfile: { profileID in
                    _ = profileManager.openWindow(for: profileID)
                },
                onClose: { windowModel.setTemporaryContext(nil) }
            )
        case .drawer:
            EmptyView()
        }
    }
}
