import DenDomain
import DenPresentationModels
import DenViews
import SFSafeSymbols
import SwiftUI

struct DenView<Header: View>: View {
    private let profileName: String?
    private let profileColor: Color
    private let isPrivateDen: Bool
    private let shouldShowHeader: Bool
    private let header: Header

    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(ProfileManager.self) private var profileManager
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    init(
        profileName: String? = nil,
        profileColor: Color = .blue,
        isPrivateDen: Bool = false,
        shouldShowHeader: Bool,
        @ViewBuilder header: () -> Header
    ) {
        self.profileName = profileName
        self.profileColor = profileColor
        self.isPrivateDen = isPrivateDen
        self.shouldShowHeader = shouldShowHeader
        self.header = header()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                NavigationSplitView(columnVisibility: boardRailVisibility) {
                    BoardRail(profileColor: profileColor)
                        .navigationSplitViewColumnWidth(min: 192, ideal: 208, max: 224)
                        .accessibilityHidden(windowModel.temporaryContext != nil)
                } detail: {
                    VStack(spacing: 0) {
                        if shouldShowHeader {
                            header
                                .frame(maxWidth: .infinity)
                                .frame(height: DenLayout.denHeaderHeight)
                                .accessibilityHidden(windowModel.temporaryContext != nil)
                        }

                        GeometryReader { detailGeometry in
                            denContent(in: detailGeometry.size)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: windowModel.isZenViewPresented ? .top : [])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    DenMotion.spatial(reduceMotion: shouldReduceMotion),
                    value: windowModel.isBoardRailPresented
                )

                DenActivePanelOverlay(
                    size: geometry.size,
                    profileName: profileName,
                    profileColor: profileColor,
                    shouldShowHeader: shouldShowHeader
                )

                DenNotificationOverlay(
                    profileColor: profileColor,
                    shouldShowHeader: shouldShowHeader
                )
                DenDrawerOverlay(
                    size: geometry.size,
                    profileColor: profileColor,
                    shouldShowHeader: shouldShowHeader
                )
                DenFeedbackOverlay(
                    profileColor: profileColor,
                    shouldReduceMotion: shouldReduceMotion,
                    activities: controller.activeDownloads
                )
                .zIndex(DenOverlayLayer.toast)
            }
            .onChange(of: preferences.sheetScale) { _, scale in
                controller.applySheetScale(scale)
            }
            .onAppear {
                controller.sheetNavigation.setReduceMotion(shouldReduceMotion)
            }
            .onChange(of: shouldReduceMotion) { _, reduceMotion in
                controller.sheetNavigation.setReduceMotion(reduceMotion)
            }
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: windowModel.temporaryContext)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: deskFilter.isPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: windowModel.isZenViewPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: windowModel.isDrawerOpen)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: preferences.drawerStyle)
        }
        .environment(windowModel.boardEditing)
        .environment(windowModel.desks)
        .environment(windowModel.overview)
        .environment(windowModel.drawer)
        .environment(windowModel.openBoard)
        .environment(windowModel.deskFilter)
        .environment(windowModel.notificationList)
        .background(
            DenBackground(
                isDenMode: windowModel.isDenMode,
                isPrivateDen: isPrivateDen,
                profileColor: profileColor)
        )
        .frame(
            minWidth: DenLayout.minimumWindowWidth,
            minHeight: DenLayout.minimumWindowHeight
        )
        .navigationTitle(titlebarTitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("den-content")
        .accessibilityLabel(contentAccessibilityValue)
        .accessibilityValue(contentAccessibilityValue)
        .modifier(DenDialogs())
        .transaction(value: windowModel.boardMutationAnimationSuppressionRequest) { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var boardRailVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                windowModel.isBoardRailPresented && !windowModel.isZenViewPresented
                    ? .doubleColumn
                    : .detailOnly
            },
            set: { visibility in
                guard !windowModel.isZenViewPresented else { return }
                windowModel.setBoardRailPresented(visibility != .detailOnly)
            }
        )
    }

    private var deskFilter: DeskFilterModel { windowModel.deskFilter }

    @ViewBuilder
    private func denContent(in size: CGSize) -> some View {
        ZStack(alignment: .top) {
            boardStrip(in: size)
                .allowsHitTesting(
                    windowModel.temporaryContext == nil && controller.focusedDesk?.boards.isEmpty == false
                )
                .accessibilityHidden(
                    windowModel.temporaryContext != nil || controller.focusedDesk?.boards.isEmpty != false
                )

            if controller.focusedDesk?.boards.isEmpty != false {
                EmptyDenView(
                    openBoard: { windowModel.showOpenBoardPanel() },
                    openTutorial: {
                        controller.openTutorialBoard(preferredWidth: newBoardWidth(in: size))
                    },
                    showKeyboardShortcuts: windowModel.showKeyboardShortcuts
                )
                .allowsHitTesting(windowModel.temporaryContext == nil)
                .accessibilityHidden(windowModel.temporaryContext != nil)
            }

            if deskFilter.isPresented && deskFilter.filteredBoards.isEmpty {
                ContentUnavailableView.search(text: deskFilter.query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            if deskFilter.isPresented {
                DeskFilterOverlay(profileColor: profileColor)
                    .zIndex(DenOverlayLayer.deskFilter)
            }

            BoardStripIndicator(profileColor: profileColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            windowModel.updateBoardLayout(
                availableWidth: size.width - DenLayout.outerInset * 2,
                spacing: DenLayout.outerInset
            )
        }
        .onChange(of: size.width) { _, width in
            windowModel.updateBoardLayout(
                availableWidth: width - DenLayout.outerInset * 2,
                spacing: DenLayout.outerInset
            )
        }
    }

    private var contentAccessibilityValue: String {
        let inputContext = windowModel.isDenMode ? "Den Mode" : "Sheet Input"
        return windowModel.isFocusModePresented ? "\(inputContext), Focus Mode" : inputContext
    }

    private var titlebarTitle: String {
        let profileTitle = profileName ?? "Den"
        guard windowModel.temporaryContext == nil, controller.focusedBoard != nil else {
            return profileTitle
        }
        return "\(profileTitle) · \(windowModel.isDenMode ? "DEN MODE" : "SHEET INPUT")"
    }

    private func newBoardWidth(in size: CGSize) -> Double {
        DenLayout.newBoardWidth(in: size, focusedBoardWidth: controller.focusedBoard?.width)
    }

    private func boardStrip(in size: CGSize) -> some View {
        BoardStrip(
            size: size,
            shouldShowHeader: false,
            profileColor: profileColor,
            boardSpacing: DenLayout.outerInset,
            boardHorizontalPadding: DenLayout.outerInset,
            onOpenBoardAtEnd: { boardID in
                windowModel.showOpenBoardPanel(afterBoardID: boardID)
            }
        )
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}

extension DenView where Header == EmptyView {
    init(profileName: String? = nil, profileColor: Color = .blue) {
        self.init(profileName: profileName, profileColor: profileColor, shouldShowHeader: false) {
            EmptyView()
        }
    }
}

private struct DenDrawerOverlay: View {
    let size: CGSize
    let profileColor: Color
    let shouldShowHeader: Bool

    @Environment(DenController.self) private var controller
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
                        DrawerWebSurface(webView: controller.drawerRuntime(for: item).webView, isFocused: isFocused)
                    },
                    placeFromContextMenu: { _ = controller.placeDrawerItemAsBoard($0) },
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
    @Environment(DenController.self) private var controller
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
                newBoardWidth: DenLayout.newBoardWidth(in: size, focusedBoardWidth: controller.focusedBoard?.width),
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
                    sourceItems: UniversalSearchActions.items(
                        controller: controller, profiles: profileManager.profiles, profileName: profileName ?? ""),
                    recentItems: controller.recentItems, boards: controller.state.desks.flatMap(\.boards),
                    perform: { target, inDrawer in
                        UniversalSearchActions.perform(
                            target, controller: controller, windowModel: windowModel, inDrawer: inDrawer,
                            openProfile: { id in
                                profileManager.profile(id: id) != nil && profileManager.openWindow(for: id)
                            }, openSettings: { openSettings() })
                    }, restoreInput: { controller.restoreFocusedFirstResponder() }))
        case .essentialsPrefix:
            panelOverlay(
                EssentialsPrefixPanel(
                    profileColor: profileColor,
                    essentials: controller.essentials,
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
                    presets: controller.deskPresets,
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
                    initialLabel: controller.focusedDesk?.label ?? "",
                    previewBoards: DeskPresetBoard.capture(from: controller.focusedDesk?.boards ?? []),
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
            controller.restoreFocusedFirstResponder()
        case .essentialsPrefix:
            windowModel.exitEssentialsPrefix()
        case .openBoard:
            windowModel.hideOpenBoardPanel()
            controller.restoreFocusedFirstResponder()
        case .zmxSessions:
            windowModel.hideZmxSessions()
        case .zmxDuplication:
            windowModel.hideZmxDuplicationPanel()
            controller.restoreFocusedFirstResponder()
        case .editBoardLink:
            windowModel.hideEditBoardLinkPanel()
            controller.restoreFocusedFirstResponder()
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
