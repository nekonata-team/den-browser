import DenApplication
import DenDomain
import DenPresentationModels
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
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let isBottom = preferences.drawerStyle == .bottom

        ZStack(alignment: isBottom ? .bottom : .center) {
            if windowModel.isDrawerOpen {
                dismissBlocker(onDismiss: windowModel.closeDrawer)
                    .transition(.opacity)

                DrawerView(
                    availableHeight: size.height,
                    availableWidth: size.width,
                    profileColor: profileColor,
                    shouldShowHeader: shouldShowHeader,
                    isDenMode: { windowModel.isDenMode },
                    isDrawerOpen: { windowModel.isDrawerOpen },
                    motionPreference: preferences.motionPreference,
                    peek: { item, isFocused in
                        DrawerWebSurface(
                            webView: session.drawer.drawerRuntime(for: item).webView, isFocused: isFocused)
                    },
                    placeFromContextMenu: { _ = session.drawer.placeDrawerItemAsBoard($0) },
                    placeAsBoard: { _ = windowModel.placeDrawerItemAsBoard($0) }
                )
                .padding(.horizontal, isBottom ? DenLayout.outerInset : 0)
                .transition(
                    isBottom
                        ? DenMotion.transition(reduceMotion: shouldReduceMotion, edge: .bottom)
                        : DenMotion.panelTransition(reduceMotion: shouldReduceMotion)
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(windowModel.isDrawerOpen)
        .zIndex(DenOverlayLayer.drawer)
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        if windowModel.temporaryContext != nil, windowModel.temporaryContext != .drawer {
            dismissBlocker(onDismiss: dismissTemporaryPresentation)
                .frame(width: size.width, height: size.height)
                .zIndex(DenOverlayLayer.activePanel)

            activePanel(
                newBoardWidth: DenLayout.newBoardWidth(
                    in: size, focusedBoardWidth: session.navigation.focusedBoard?.width),
                boardHeight: DenLayout.boardHeight(for: size, shouldShowHeader: shouldShowHeader)
            )
            .zIndex(DenOverlayLayer.activePanel)
        }
    }

    @ViewBuilder
    private func activePanel(newBoardWidth: CGFloat, boardHeight: CGFloat) -> some View {
        switch windowModel.temporaryContext {
        case .universalSearch:
            panelOverlay(
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
                    }, restoreInput: { session.runtimes.restoreFocusedFirstResponder() }))
        case .essentialsPrefix:
            panelOverlay(
                EssentialsPrefixPanel(
                    profileColor: profileColor,
                    essentials: session.configuration.preferences.essentials,
                    selectedEssentialID: windowModel.selectedEssentialID,
                    onSelect: { windowModel.selectEssential($0) },
                    onOpenInDrawer: { windowModel.launchEssential(id: $0, inDrawer: true) }
                )
            )
        case .openBoard:
            panelOverlay(OpenBoardPanel(profileColor: profileColor, newBoardWidth: newBoardWidth))
        case .zmxSessions:
            panelOverlay(ZmxSessionsPanel(profileColor: profileColor))
        case .zmxDuplication:
            panelOverlay(ZmxDuplicationPanel())
        case .editBoardLink:
            panelOverlay(EditBoardLinkPanel())
        case .newDesk, .replaceDesk:
            panelOverlay(NewDeskPanel(profileColor: profileColor, boardHeight: boardHeight))
        case .deskPresetManagement:
            panelOverlay(
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
            )
        case .boardWidth:
            panelOverlay(BoardWidthPanel())
        case .saveDeskPreset:
            panelOverlay(
                SaveDeskPresetPanel(
                    initialLabel: session.navigation.focusedDesk?.label ?? "",
                    previewBoards: DeskPresetBoard.capture(from: session.navigation.focusedDesk?.boards ?? []),
                    boardHeight: boardHeight,
                    savePreset: windowModel.deskPresetActions.save,
                    onClose: { windowModel.hideSaveDeskPresetPanel() }
                )
            )
        case .renameBoard:
            panelOverlay(RenameBoardPanel())
        case .renameDesk:
            panelOverlay(RenameDeskPanel())
        case .saveEssential:
            panelOverlay(SaveEssentialPanel())
        case .overview:
            OverviewView(profileColor: profileColor, boardHeight: boardHeight)
                .padding(DenLayout.overlayInset)
                .transition(DenMotion.panelTransition(reduceMotion: shouldReduceMotion))
        case .boardActivity:
            BoardActivityView(profileColor: profileColor)
                .padding(DenLayout.overlayInset)
                .transition(DenMotion.panelTransition(reduceMotion: shouldReduceMotion))
        case .keyboardShortcuts:
            panelOverlay(
                KeyboardShortcutsView(onClose: windowModel.hideKeyboardShortcuts)
                    .denPanel(width: DenPanelLayout.wideWidth)
            )
        case .profilePicker:
            panelOverlay(
                OpenProfilePanel(
                    profiles: profileManager.profiles,
                    profileColor: profileColor,
                    onOpenProfile: { profileID in
                        _ = profileManager.openWindow(for: profileID)
                    },
                    onClose: { windowModel.setTemporaryContext(nil) }
                )
            )
        case .drawer, nil:
            EmptyView()
        }
    }

    private func panelOverlay<Content: View>(_ content: Content) -> some View {
        content
            .transition(DenMotion.panelTransition(reduceMotion: shouldReduceMotion))
            .padding(.top, 160)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func dismissTemporaryPresentation() {
        switch windowModel.temporaryContext {
        case .universalSearch:
            windowModel.hideUniversalSearch()
            session.runtimes.restoreFocusedFirstResponder()
        case .essentialsPrefix:
            windowModel.exitEssentialsPrefix()
        case .openBoard:
            windowModel.hideOpenBoardPanel()
            session.runtimes.restoreFocusedFirstResponder()
        case .zmxSessions:
            windowModel.hideZmxSessions()
        case .zmxDuplication:
            windowModel.hideZmxDuplicationPanel()
            session.runtimes.restoreFocusedFirstResponder()
        case .editBoardLink:
            windowModel.hideEditBoardLinkPanel()
            session.runtimes.restoreFocusedFirstResponder()
        case .newDesk, .replaceDesk:
            windowModel.hideNewDeskPanel()
        case .deskPresetManagement:
            windowModel.hideNewDeskPanel(exitsDenMode: true)
        case .overview:
            windowModel.hideOverview()
        case .boardActivity:
            windowModel.hideBoardActivity()
        case .keyboardShortcuts:
            windowModel.hideKeyboardShortcuts()
        case .boardWidth:
            windowModel.hideBoardWidthPanel()
        case .saveDeskPreset:
            windowModel.hideSaveDeskPresetPanel()
        case .renameBoard:
            windowModel.hideRenameBoardPanel()
        case .renameDesk:
            windowModel.hideRenameDeskPanel()
        case .drawer:
            windowModel.closeDrawer()
        case .saveEssential:
            windowModel.hideSaveEssentialPanel()
        case .profilePicker:
            windowModel.setTemporaryContext(nil)
        case nil:
            break
        }
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}
