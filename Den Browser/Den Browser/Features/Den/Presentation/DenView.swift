import DenDesign
import DenDomain
import SFSafeSymbols
import SwiftUI

private enum DenOverlayLayer {
    static let activePanel: Double = 1
    static let deskFilter: Double = 2
    static let drawer: Double = 3
    static let notificationDismissArea: Double = 4
    static let notificationList: Double = 5
    static let toast: Double = 10
}

struct DenView<Header: View>: View {
    private let profileName: String?
    private let profileColor: Color
    private let isPrivateDen: Bool
    private let shouldShowHeader: Bool
    private let header: Header

    @Environment(DenStore.self) private var store
    @Environment(DenViewModel.self) private var viewModel
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
                        .accessibilityHidden(viewModel.temporaryContext != nil)
                        .overlay {
                            if viewModel.temporaryContext != nil {
                                panelDismissBlocker
                            }
                        }
                } detail: {
                    VStack(spacing: 0) {
                        if shouldShowHeader {
                            header
                                .frame(maxWidth: .infinity)
                                .frame(height: DenLayout.denHeaderHeight)
                                .accessibilityHidden(viewModel.temporaryContext != nil)
                                .overlay {
                                    if viewModel.temporaryContext != nil {
                                        panelDismissBlocker
                                    }
                                }
                        }

                        GeometryReader { detailGeometry in
                            denContent(in: detailGeometry.size)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: viewModel.isZenViewPresented ? .top : [])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(
                    DenMotion.spatial(reduceMotion: shouldReduceMotion),
                    value: viewModel.isBoardRailPresented
                )

                notificationsOverlay
                    .zIndex(DenOverlayLayer.notificationList)
                drawerOverlay(in: geometry.size)
                    .zIndex(DenOverlayLayer.drawer)
                feedbackOverlay
                    .zIndex(DenOverlayLayer.toast)
            }
            .onChange(of: preferences.sheetScale) { _, scale in
                store.applySheetScale(scale)
            }
            .onAppear {
                store.sheetNavigation.setReduceMotion(shouldReduceMotion)
            }
            .onChange(of: shouldReduceMotion) { _, reduceMotion in
                store.sheetNavigation.setReduceMotion(reduceMotion)
            }
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: viewModel.temporaryContext)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: deskFilter.isPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: viewModel.isZenViewPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: viewModel.isDrawerOpen)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: preferences.drawerStyle)
        }
        .environment(viewModel.overview)
        .environment(viewModel.drawer)
        .environment(viewModel.openBoard)
        .environment(viewModel.deskFilter)
        .environment(viewModel.notificationList)
        .background(
            DenBackground(
                isDenMode: viewModel.isDenMode,
                isPrivateDen: isPrivateDen,
                profileColor: profileColor)
        )
        .frame(minWidth: 800, minHeight: 720)
        .navigationTitle(titlebarTitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("den-content")
        .accessibilityLabel(contentAccessibilityValue)
        .accessibilityValue(contentAccessibilityValue)
        .modifier(DenDialogs())
        .transaction(value: viewModel.boardMutationAnimationSuppressionRequest) { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var boardRailVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                viewModel.isBoardRailPresented && !viewModel.isZenViewPresented
                    ? .doubleColumn
                    : .detailOnly
            },
            set: { visibility in
                guard !viewModel.isZenViewPresented else { return }
                viewModel.setBoardRailPresented(visibility != .detailOnly)
            }
        )
    }

    private var deskFilter: DeskFilterViewModel { viewModel.deskFilter }

    @ViewBuilder
    private func denContent(in size: CGSize) -> some View {
        ZStack(alignment: .top) {
            boardStrip(in: size)
                .allowsHitTesting(
                    viewModel.temporaryContext == nil && store.focusedDesk?.boards.isEmpty == false
                )
                .accessibilityHidden(
                    viewModel.temporaryContext != nil || store.focusedDesk?.boards.isEmpty != false
                )

            if store.focusedDesk?.boards.isEmpty != false {
                EmptyDenView(
                    openBoard: { viewModel.showOpenBoardPanel() },
                    openTutorial: {
                        store.openTutorialBoard(preferredWidth: newBoardWidth(in: size))
                    },
                    showKeyboardShortcuts: viewModel.showKeyboardShortcuts
                )
                .allowsHitTesting(viewModel.temporaryContext == nil)
                .accessibilityHidden(viewModel.temporaryContext != nil)
            }

            if deskFilter.isPresented && deskFilter.filteredBoards.isEmpty {
                ContentUnavailableView.search(text: deskFilter.query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            if deskFilter.isPresented {
                DeskFilterOverlay(profileColor: profileColor)
                    .padding(.top, DenLayout.outerInset)
                    .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                    .zIndex(DenOverlayLayer.deskFilter)
            }

            if viewModel.temporaryContext != nil, viewModel.temporaryContext != .drawer {
                panelDismissBlocker
                    .frame(width: size.width, height: size.height)
                    .zIndex(DenOverlayLayer.activePanel)
            }

            activePanel(
                newBoardWidth: newBoardWidth(in: size),
                boardHeight: DenLayout.boardHeight(for: size, shouldShowHeader: false)
            )
            .zIndex(DenOverlayLayer.activePanel)

            indicatorOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.updateBoardLayout(
                availableWidth: size.width - DenLayout.outerInset * 2,
                spacing: DenLayout.outerInset
            )
        }
        .onChange(of: size.width) { _, width in
            viewModel.updateBoardLayout(
                availableWidth: width - DenLayout.outerInset * 2,
                spacing: DenLayout.outerInset
            )
        }
    }

    private var contentAccessibilityValue: String {
        let inputContext = viewModel.isDenMode ? "Den Mode" : "Sheet Input"
        return viewModel.isFocusModePresented ? "\(inputContext), Focus Mode" : inputContext
    }

    private var titlebarTitle: String {
        let profileTitle = profileName ?? "Den"
        guard viewModel.temporaryContext == nil, store.focusedBoard != nil else {
            return profileTitle
        }
        return "\(profileTitle) · \(viewModel.isDenMode ? "DEN MODE" : "SHEET INPUT")"
    }

    @ViewBuilder
    private func activePanel(newBoardWidth: CGFloat, boardHeight: CGFloat) -> some View {
        switch viewModel.temporaryContext {
        case .essentialsPrefix:
            panelOverlay(
                EssentialsPrefixPanel(
                    profileColor: profileColor,
                    essentials: store.essentials,
                    selectedEssentialID: viewModel.selectedEssentialID,
                    onSelect: { viewModel.selectEssential($0) }
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
            panelOverlay(newDeskPanel)
        case .deskPresetManagement:
            panelOverlay(
                DeskPresetManagementPanel(isStandalone: true, profileColor: profileColor) {
                    viewModel.hideNewDeskPanel(exitsDenMode: true)
                })
        case .boardWidth:
            panelOverlay(boardWidthPanel)
        case .saveDeskPreset:
            panelOverlay(SaveDeskPresetPanel())
        case .renameBoard:
            panelOverlay(RenameBoardPanel())
        case .renameDesk:
            panelOverlay(RenameDeskPanel())
        case .saveEssential:
            panelOverlay(saveEssentialPanel)
        case .overview:
            OverviewView(profileColor: profileColor, boardHeight: boardHeight)
                .padding(DenLayout.overlayInset)
                .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.98))
        case .boardActivity:
            BoardActivityView(profileColor: profileColor)
                .padding(DenLayout.overlayInset)
                .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.98))
        case .keyboardShortcuts:
            KeyboardShortcutsView(onClose: viewModel.hideKeyboardShortcuts)
                .padding(DenKeyboardShortcutsLayout.guidePadding)
                .frame(
                    width: DenKeyboardShortcutsLayout.guideSize.width,
                    height: DenKeyboardShortcutsLayout.guideSize.height
                )
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
                )
                .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.98))
        case .profilePicker:
            panelOverlay(
                OpenProfilePanel(
                    profiles: profileManager.profiles,
                    profileColor: profileColor,
                    onOpenProfile: { profileID in
                        if !profileManager.activateWindow(for: profileID) {
                            openWindow(value: ProfileWindowRoute(profileID: profileID))
                        }
                    },
                    onClose: { viewModel.setTemporaryContext(nil) }
                )
            )
        case .drawer, nil:
            EmptyView()
        }
    }

    private func panelOverlay<Content: View>(_ content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .padding(
                    .top,
                    shouldShowHeader
                        ? DenLayout.panelGap
                        : DenLayout.outerInset
                )
                .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var panelDismissBlocker: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissTemporaryPresentation)
            .accessibilityHidden(true)
    }

    private func dismissTemporaryPresentation() {
        switch viewModel.temporaryContext {
        case .essentialsPrefix:
            viewModel.exitEssentialsPrefix()
        case .openBoard:
            viewModel.hideOpenBoardPanel()
            store.restoreFocusedFirstResponder()
        case .zmxSessions:
            viewModel.hideZmxSessions()
        case .zmxDuplication:
            viewModel.hideZmxDuplicationPanel()
            store.restoreFocusedFirstResponder()
        case .editBoardLink:
            viewModel.hideEditBoardLinkPanel()
            store.restoreFocusedFirstResponder()
        case .newDesk, .replaceDesk:
            viewModel.hideNewDeskPanel()
        case .deskPresetManagement:
            viewModel.hideNewDeskPanel(exitsDenMode: true)
        case .overview:
            viewModel.hideOverview()
        case .boardActivity:
            viewModel.hideBoardActivity()
        case .keyboardShortcuts:
            viewModel.hideKeyboardShortcuts()
        case .boardWidth:
            viewModel.hideBoardWidthPanel()
        case .saveDeskPreset:
            viewModel.hideSaveDeskPresetPanel()
        case .renameBoard:
            viewModel.hideRenameBoardPanel()
        case .renameDesk:
            viewModel.hideRenameDeskPanel()
        case .drawer:
            viewModel.closeDrawer()
        case .saveEssential:
            viewModel.hideSaveEssentialPanel()
        case .profilePicker:
            viewModel.setTemporaryContext(nil)
        case nil:
            break
        }
    }

    private var newDeskPanel: some View {
        NewDeskPanel(profileColor: profileColor)
    }

    private func newBoardWidth(in size: CGSize) -> Double {
        DenLayout.newBoardWidth(in: size, focusedBoardWidth: store.focusedBoard?.width)
    }

    private var saveEssentialPanel: some View {
        SaveEssentialPanel()
    }

    private var boardWidthPanel: some View {
        BoardWidthPanel()
    }

    private func boardStrip(in size: CGSize) -> some View {
        BoardStrip(
            size: size,
            shouldShowHeader: false,
            profileColor: profileColor,
            boardSpacing: DenLayout.outerInset,
            boardHorizontalPadding: DenLayout.outerInset,
            onOpenBoardAtEnd: { boardID in
                viewModel.showOpenBoardPanel(afterBoardID: boardID)
            }
        )
    }

    @ViewBuilder
    private var notificationsOverlay: some View {
        if viewModel.isNotificationListPresented {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.closeNotificationList() }
                .accessibilityHidden(true)
                .zIndex(DenOverlayLayer.notificationDismissArea)

            NotificationListView(
                profileColor: profileColor
            )
            .padding(
                .top,
                shouldShowHeader
                    ? DenLayout.denHeaderHeight + DenLayout.panelGap
                    : DenLayout.outerInset
            )
            .padding(.trailing, DenLayout.outerInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
            .zIndex(DenOverlayLayer.notificationList)
        }
    }

    @ViewBuilder
    private func drawerOverlay(in size: CGSize) -> some View {
        let isBottom = preferences.drawerStyle == .bottom

        ZStack(alignment: isBottom ? .bottom : .center) {
            if viewModel.isDrawerOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.closeDrawer()
                    }
                    .accessibilityHidden(true)
                    .transition(.opacity)

                DrawerView(
                    availableHeight: size.height,
                    availableWidth: size.width,
                    profileColor: profileColor,
                    shouldShowHeader: shouldShowHeader
                )
                .padding(.horizontal, isBottom ? DenLayout.outerInset : 0)
                .transition(
                    isBottom
                        ? DenMotion.transition(reduceMotion: shouldReduceMotion, edge: .bottom)
                        : DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96)
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(viewModel.isDrawerOpen)
        .zIndex(DenOverlayLayer.drawer)
    }

    @ViewBuilder
    private var feedbackOverlay: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(store.activeDownloads) { activity in
                DownloadActivityView(activity: activity, tint: profileColor)
                    .transition(feedbackTransition)
            }

            if let toast = viewModel.displayedFeedback {
                ToastView(toast: toast) {
                    viewModel.handleTap(on: toast)
                }
                .transition(feedbackTransition)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(
            DenMotion.feedback(reduceMotion: shouldReduceMotion),
            value: store.activeDownloads.map(\.id)
        )
        .zIndex(DenOverlayLayer.toast)
    }

    private var feedbackTransition: AnyTransition {
        systemReduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    @ViewBuilder
    private var indicatorOverlay: some View {
        if shouldShowBoardIndicator {
            boardIndicator
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, DenLayout.outerInset)
                .allowsHitTesting(viewModel.temporaryContext == nil)
                .accessibilityHidden(viewModel.temporaryContext != nil)
                .transition(.opacity)
        }
    }

    private var shouldShowBoardIndicator: Bool {
        !viewModel.isZenViewPresented
            && viewModel.temporaryContext == nil
            && (store.focusedDesk?.boards.count ?? 0) > 1
    }

    private var boardIndicator: some View {
        let boards =
            deskFilter.isPresented
            ? deskFilter.filteredBoards
            : store.focusedDesk?.boards ?? []
        let focusedBoardID =
            deskFilter.isPresented
            ? deskFilter.selectionBoardID
            : store.focusedDesk?.focusedBoardID

        return BoardStripIndicator(
            boards: boards,
            focusedBoardID: focusedBoardID,
            anchorBoardID: store.focusedDesk?.anchorBoardID,
            profileColor: profileColor,
            reduceMotion: shouldReduceMotion,
            onSelect: { store.focusBoard($0) }
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

private struct DeskFilterOverlay: View {
    @Environment(DeskFilterViewModel.self) private var deskFilter
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let profileColor: Color
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .magnifyingglass)
                .foregroundStyle(deskFilter.isInputActive ? .primary : .secondary)
                .accessibilityHidden(true)

            TextField(
                text: Binding(
                    get: { deskFilter.query },
                    set: { deskFilter.setQuery($0) }
                ),
                prompt: Text("Filter boards")
            ) {
                Text("Filter Boards")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($isFocused)
            .disabled(!deskFilter.isInputActive)
            .accessibilityIdentifier("desk-filter-input")

            Text("\(deskFilter.filteredBoards.count)/\(deskFilter.totalBoardCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: DenLayout.deskFilterWidth)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .stroke(
                    deskFilter.isInputActive
                        ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.86))
                        : Color.primary.opacity(0.16),
                    lineWidth: deskFilter.isInputActive ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .onTapGesture {
            deskFilter.enter()
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = deskFilter.isInputActive
            }
        }
        .onChange(of: deskFilter.isInputActive) { _, isActive in
            isFocused = isActive
        }
        .onChange(of: deskFilter.query) { _, newValue in
            if isFocused {
                TextInputComposition.syncActiveFieldEditor(to: newValue)
            }
        }
        .accessibilityIdentifier("desk-filter")
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "dev.nekonata.denbrowser.preview") ?? .standard
    let preferences = AppPreferences(defaults: defaults)
    let sheetNavigation = SheetNavigationManager(defaults: defaults)
    let store = DenStore(
        state: .sample,
        websiteDataStore: .nonPersistent(),
        sheetNavigation: sheetNavigation,
        preferences: preferences)
    let viewModel = DenViewModel(store: store)
    DenView()
        .environment(store)
        .environment(viewModel)
        .environment(preferences)
        .onAppear { viewModel.connect() }
        .onDisappear { viewModel.disconnect() }
}

private struct BoardStripIndicator: View {
    private static let dotHeight: CGFloat = 6

    let boards: [BoardState]
    let focusedBoardID: UUID?
    let anchorBoardID: UUID?
    let profileColor: Color
    let reduceMotion: Bool
    let onSelect: (UUID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(boards) { board in
                let isFocused = board.id == focusedBoardID
                let isAnchor = board.id == anchorBoardID
                Button {
                    onSelect(board.id)
                } label: {
                    Capsule()
                        .fill(
                            isAnchor
                                ? profileColor.opacity(isFocused ? 1 : 0.72)
                                : Color.primary.opacity(isFocused ? 1 : 0.28)
                        )
                        .frame(width: isFocused ? 18 : Self.dotHeight, height: Self.dotHeight)
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(board.displayName)
                .accessibilityLabel(
                    isAnchor
                        ? "\(board.displayName) Board, Anchor Board"
                        : "\(board.displayName) Board"
                )
            }
        }
        .frame(height: Self.dotHeight)
        .animation(DenMotion.spatial(reduceMotion: reduceMotion), value: focusedBoardID)
        .animation(DenMotion.spatial(reduceMotion: reduceMotion), value: boards.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-strip-indicator")
    }
}
