import Foundation
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class DenStorage {
    var state: DenState
    var deskPresets: [PersonalDeskPreset]
    var recentItems: [RecentItem]
    var notifications: [DenNotification] = []
    var activeDrag: ActiveDrag?
    var recentlyRemovedBoards: [RecentlyRemovedBoard] = []
    var recentlyDiscardedDrawerItems: [DrawerItem] = []

    @ObservationIgnored var runtimes: [UUID: BoardRuntime] = [:]
    @ObservationIgnored var terminalRuntimes: [UUID: TerminalRuntime] = [:]
    @ObservationIgnored var runtimeOwners: [UUID: DenStore] = [:]
    @ObservationIgnored let onSave: ((DenState) -> Void)?
    @ObservationIgnored let onDeskPresetsSave: (([PersonalDeskPreset]) -> Void)?
    @ObservationIgnored let onRecentItemsSave: (([RecentItem]) -> Bool)?

    init(
        state: DenState,
        deskPresets: [PersonalDeskPreset] = [],
        recentItems: [RecentItem] = [],
        onSave: ((DenState) -> Void)? = nil,
        onDeskPresetsSave: (([PersonalDeskPreset]) -> Void)? = nil,
        onRecentItemsSave: (([RecentItem]) -> Bool)? = nil
    ) {
        self.state = state
        self.deskPresets = deskPresets
        self.recentItems = recentItems
        self.onSave = onSave
        self.onDeskPresetsSave = onDeskPresetsSave
        self.onRecentItemsSave = onRecentItemsSave
    }
}

@MainActor
@Observable
final class DenStore {
    static let maximumDeskCount = 10
    static let maximumRecentItemCount = 100
    static let maximumNotificationCount = 200
    static let maximumRecentlyRemovedBoardCount = 10
    static let maximumRecentlyDiscardedDrawerItemCount = 10
    static let maximumPersistedRecentInputLength = 2_048
    private static let toastDuration: Duration = .seconds(5)

    let storage: DenStorage
    var state: DenState {
        get { storage.state }
        set { storage.state = newValue }
    }
    var deskPresets: [PersonalDeskPreset] {
        get { storage.deskPresets }
        set { storage.deskPresets = newValue }
    }
    var recentItems: [RecentItem] {
        get { storage.recentItems }
        set { storage.recentItems = newValue }
    }
    var notifications: [DenNotification] {
        get { storage.notifications }
        set { storage.notifications = newValue }
    }
    var unreadNotificationCount: Int {
        notifications.lazy.filter { !$0.isRead }.count
    }
    var essentials: [Essential] { preferences.essentials }
    private(set) var presentedDeskID: UUID
    private(set) var temporaryContext: TemporaryContext?
    private(set) var zmxDuplicationRootSessionName: String?
    var isZenViewPresented = false
    var isFocusModePresented = false
    var isNotificationListPresented = false
    var selectedNotificationID: UUID?
    var isDenMode = false
    var isFullscreenActive = false
    var deskFilterPhase: DenFilterPhase = .inactive
    var deskFilterQuery = ""
    var deskFilterSelectionBoardID: UUID?
    var overviewQuery = ""
    var overviewFilterPhase: DenFilterPhase = .inactive
    var boardWidthPanelMessage: String?
    var openBoardPanelInitialURL: URL?
    var openBoardPanelMessage: String?
    var zmxSessionGroups: [ZmxSessionGroup] = []
    var zmxSessionProcessNames: [String: String] = [:]
    var zmxSessionsMessage: String?
    var zmxSessionsIsLoading = false
    var zmxSessionSelectedName: String?
    var zmxSessionQuery = ""
    var zmxSessionFilterPhase: DenFilterPhase = .inactive
    var zmxSessionPendingDeletion: String?
    var zmxSessionsReturnToOpenBoard = false
    var zmxSessionRefreshTask: Task<Void, Never>?
    var pendingConfirmation: PendingConfirmation?
    var maximizedBoardID: UUID?
    var centerFocusedBoardRequest = 0
    var deskFilterCenteringTask: Task<Void, Never>?
    var activeDrag: ActiveDrag? {
        get { storage.activeDrag }
        set { storage.activeDrag = newValue }
    }
    var boardDragCancellationRequest = 0
    var deskDragCancellationRequest = 0
    var overviewSelection: OverviewSelection?
    var recentlyRemovedBoards: [RecentlyRemovedBoard] {
        get { storage.recentlyRemovedBoards }
        set { storage.recentlyRemovedBoards = newValue }
    }
    var recentlyDiscardedDrawerItems: [DrawerItem] {
        get { storage.recentlyDiscardedDrawerItems }
        set { storage.recentlyDiscardedDrawerItems = newValue }
    }
    var isDrawerOpen: Bool { temporaryContext == .drawer }

    func updateZmxDuplicationRootSessionName(_ rootSessionName: String?) {
        zmxDuplicationRootSessionName = rootSessionName
    }

    var isDeskFilterPresented: Bool { deskFilterPhase != .inactive }
    var isDeskFilterInputActive: Bool { deskFilterPhase == .filtering }
    var isDeskFilterSelecting: Bool { deskFilterPhase == .selecting }
    var isOverviewFilterPresented: Bool { overviewFilterPhase != .inactive }
    var isOverviewFilterInputActive: Bool { overviewFilterPhase == .filtering }
    var isOverviewFilterSelecting: Bool { overviewFilterPhase == .selecting }
    var isDrawerFilterPresented: Bool { drawerFilterPhase != .inactive }
    var isDrawerFilterInputActive: Bool { drawerFilterPhase == .filtering }
    var isDrawerFilterSelecting: Bool { drawerFilterPhase == .selecting }
    var isBoardDragging: Bool {
        guard case .board? = activeDrag else { return false }
        return true
    }
    var isDeskDragging: Bool {
        guard case .desk? = activeDrag else { return false }
        return true
    }
    var overviewSelectionDeskID: UUID? { overviewSelection?.deskID }
    var overviewSelectionBoardID: UUID? { overviewSelection?.boardID }
    var drawerQuery = ""
    var drawerFilterPhase: DenFilterPhase = .inactive
    var selectedDrawerItemID: UUID?
    var expandedDrawerItemID: UUID? { state.expandedDrawerItemID }
    private(set) var toastMessage: ToastMessage?
    let sheetNavigation: SheetNavigationManager
    let preferences: AppPreferences
    let websiteDataStore: WKWebsiteDataStore
    var zellijClient: ZellijClient {
        ZellijClient(executablePath: preferences.zellijPath)
    }
    var zmxClient: ZmxClient {
        ZmxClient(
            executablePath: preferences.zmxPath,
            commandRunner: terminalCommandRunner)
    }
    private(set) var webExtensionHost: WebExtensionHost?
    private(set) var webExtensionWindow: MV3WebExtensionWindow?

    var runtimes: [UUID: BoardRuntime] {
        get { storage.runtimes }
        set { storage.runtimes = newValue }
    }
    var terminalRuntimes: [UUID: TerminalRuntime] {
        get { storage.terminalRuntimes }
        set { storage.terminalRuntimes = newValue }
    }
    @ObservationIgnored var drawerPreviewRuntime: DrawerPreviewRuntime?
    @ObservationIgnored var toastTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTerminalURLSuppressions: [URL: (count: Int, expiresAt: Date)] = [:]
    @ObservationIgnored private var previousFocusedDeskID: UUID?
    @ObservationIgnored private let terminalCommandRunner: any TerminalCommandRunning
    @ObservationIgnored let canPresentDesk: ((UUID) -> Bool)?
    @ObservationIgnored private let onDeskPresentationRequest: ((UUID) -> Bool)?
    @ObservationIgnored private let onWillResetDen: (() -> Void)?
    var onRecentItemsSave: (([RecentItem]) -> Bool)? { storage.onRecentItemsSave }
    var boardLayoutMetrics: BoardLayoutMetrics?

    // ponytail: one-second handoff window; replace with source-aware URL routing if available.
    private static let terminalURLSuppressionDuration: TimeInterval = 1

    func registerTerminalURL(_ url: URL) {
        let canonicalURL = SheetURLPolicy.canonicalSheetURL(url)
        let expiration = Date().addingTimeInterval(Self.terminalURLSuppressionDuration)
        if let pending = pendingTerminalURLSuppressions[canonicalURL], pending.expiresAt > Date() {
            pendingTerminalURLSuppressions[canonicalURL] = (pending.count + 1, expiration)
        } else {
            pendingTerminalURLSuppressions[canonicalURL] = (1, expiration)
        }
    }

    func handleExternalURL(_ url: URL) {
        let canonicalURL = SheetURLPolicy.canonicalSheetURL(url)
        guard !consumeTerminalURLSuppression(canonicalURL) else { return }

        switch preferences.externalLinkDestination {
        case .drawerPreview:
            keepInDrawer(url)
        case .focusedBoard:
            addBoard(
                urlString: url.absoluteString,
                preferredWidth: focusedBoard?.width,
                afterBoardID: focusedBoard?.id)
        }
    }

    func cancelTerminalURLRegistration(_ url: URL) {
        _ = consumeTerminalURLSuppression(SheetURLPolicy.canonicalSheetURL(url))
    }

    private func consumeTerminalURLSuppression(_ url: URL) -> Bool {
        guard let pending = pendingTerminalURLSuppressions[url] else { return false }
        guard pending.expiresAt > Date() else {
            pendingTerminalURLSuppressions.removeValue(forKey: url)
            return false
        }
        if pending.count == 1 {
            pendingTerminalURLSuppressions.removeValue(forKey: url)
        } else {
            pendingTerminalURLSuppressions[url] = (pending.count - 1, pending.expiresAt)
        }
        return true
    }

    var focusedDesk: DeskState? {
        state.desks.first { $0.id == presentedDeskID }
    }

    var focusedBoard: BoardState? {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return nil }
        return state.desks[deskIndex].boards[boardIndex]
    }

    func updateWebExtensionHost(
        _ host: WebExtensionHost?,
        window: MV3WebExtensionWindow?
    ) {
        guard webExtensionHost !== host || webExtensionWindow !== window else { return }
        releaseWebRuntimes()
        webExtensionHost = host
        webExtensionWindow = window
    }

    var contentInputLabel: String {
        focusedBoard?.isTerminal == true ? "Terminal Input" : "Sheet Input"
    }

    var canCreateDesk: Bool {
        state.desks.count < Self.maximumDeskCount
    }

    var canDeleteFocusedDesk: Bool {
        state.desks.count > 1
            && state.desks.contains { $0.id != presentedDeskID && (canPresentDesk?($0.id) ?? true) }
    }

    var isOpenBoardPanelPresented: Bool { temporaryContext == .openBoard }
    var isZmxSessionsPresented: Bool { temporaryContext == .zmxSessions }
    var isZmxSessionFilterInputActive: Bool { zmxSessionFilterPhase == .filtering }
    var isNewDeskPanelPresented: Bool {
        temporaryContext == .newDesk
            || temporaryContext == .replaceDesk
            || temporaryContext == .deskPresetManagement
    }
    var isReplaceDeskPanelPresented: Bool { temporaryContext == .replaceDesk }
    var isDeskPresetManagementPresented: Bool { temporaryContext == .deskPresetManagement }
    var isOverviewPresented: Bool { temporaryContext == .overview }
    var isBoardActivityPresented: Bool { temporaryContext == .boardActivity }
    var isKeyboardShortcutsPresented: Bool { temporaryContext == .keyboardShortcuts }
    var isBoardWidthPanelPresented: Bool { temporaryContext == .boardWidth }
    var isSaveDeskPresetPanelPresented: Bool { temporaryContext == .saveDeskPreset }
    var deskPendingDeletion: DeskState? {
        guard case .deleteDesk(let desk)? = pendingConfirmation else { return nil }
        return desk
    }
    var deskPendingReplacement: PendingDeskReplacement? {
        guard case .replaceDesk(let replacement)? = pendingConfirmation else { return nil }
        return replacement
    }
    var deskPresetPendingDeletion: PersonalDeskPreset? {
        guard case .deleteDeskPreset(let preset)? = pendingConfirmation else { return nil }
        return preset
    }
    var deskPresetPendingReplacement: PersonalDeskPreset? {
        guard case .replaceDeskPreset(let preset)? = pendingConfirmation else { return nil }
        return preset
    }
    var drawerPendingDeletionCount: Int? {
        guard case .clearDrawer(let count)? = pendingConfirmation else { return nil }
        return count
    }
    var notificationPendingDeletionCount: Int? {
        guard case .clearNotifications(let count)? = pendingConfirmation else { return nil }
        return count
    }
    var isResetDenPending: Bool {
        guard case .resetDen? = pendingConfirmation else { return false }
        return true
    }
    var hasPendingConfirmation: Bool {
        pendingConfirmation != nil || zmxSessionPendingDeletion != nil
    }

    convenience init() {
        self.init(state: .sample)
    }

    convenience init(state: DenState) {
        self.init(state: state, sheetNavigation: SheetNavigationManager())
    }

    convenience init(
        state: DenState,
        sheetNavigation: SheetNavigationManager,
        preferences: AppPreferences = AppPreferences(),
        terminalCommandRunner: any TerminalCommandRunning = ProcessTerminalCommandRunner()
    ) {
        self.init(
            state: state,
            websiteDataStore: .default(),
            sheetNavigation: sheetNavigation,
            preferences: preferences,
            terminalCommandRunner: terminalCommandRunner,
            deskPresets: [],
            onSave: nil,
            onRecentItemsSave: nil
        )
    }

    convenience init(state: DenState, onSave: @escaping (DenState) -> Void) {
        self.init(
            state: state,
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            preferences: AppPreferences(),
            deskPresets: [],
            onSave: onSave,
            onRecentItemsSave: nil
        )
    }

    convenience init(
        state: DenState,
        deskPresets: [PersonalDeskPreset],
        onDeskPresetsSave: (([PersonalDeskPreset]) -> Void)? = nil
    ) {
        self.init(
            state: state,
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            preferences: AppPreferences(),
            deskPresets: deskPresets,
            onSave: nil,
            onDeskPresetsSave: onDeskPresetsSave,
            onRecentItemsSave: nil
        )
    }

    init(
        state: DenState,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        preferences: AppPreferences = AppPreferences(),
        terminalCommandRunner: any TerminalCommandRunning = ProcessTerminalCommandRunner(),
        webExtensionHost: WebExtensionHost? = nil,
        webExtensionWindow: MV3WebExtensionWindow? = nil,
        deskPresets: [PersonalDeskPreset] = [],
        recentItems: [RecentItem] = [],
        onSave: ((DenState) -> Void)?,
        onDeskPresetsSave: (([PersonalDeskPreset]) -> Void)? = nil,
        onRecentItemsSave: (([RecentItem]) -> Bool)? = nil
    ) {
        let normalizedState = Self.normalizedPersistedState(state)
        let storage = DenStorage(
            state: normalizedState,
            deskPresets: deskPresets,
            recentItems: recentItems,
            onSave: onSave,
            onDeskPresetsSave: onDeskPresetsSave,
            onRecentItemsSave: onRecentItemsSave)
        self.storage = storage
        presentedDeskID = normalizedState.focusedDeskID
        self.websiteDataStore = websiteDataStore
        self.sheetNavigation = sheetNavigation
        self.preferences = preferences
        self.terminalCommandRunner = terminalCommandRunner
        self.webExtensionHost = webExtensionHost
        self.webExtensionWindow = webExtensionWindow
        canPresentDesk = nil
        onDeskPresentationRequest = nil
        onWillResetDen = nil
        ensureFocusedObjects()
        if let restoredDrawerItemID = self.state.expandedDrawerItemID,
            self.state.drawerItems.contains(where: { $0.id == restoredDrawerItemID })
        {
            selectedDrawerItemID = restoredDrawerItemID
        } else {
            self.state.expandedDrawerItemID = nil
        }
        if self.state != state {
            onSave?(self.state)
        }
    }

    init(
        storage: DenStorage,
        presentedDeskID: UUID?,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        preferences: AppPreferences,
        webExtensionHost: WebExtensionHost? = nil,
        webExtensionWindow: MV3WebExtensionWindow? = nil,
        canPresentDesk: @escaping (UUID) -> Bool,
        onDeskPresentationRequest: @escaping (UUID) -> Bool,
        onWillResetDen: @escaping () -> Void,
        terminalCommandRunner: any TerminalCommandRunning = ProcessTerminalCommandRunner()
    ) {
        self.storage = storage
        self.presentedDeskID =
            presentedDeskID
            .flatMap { requested in storage.state.desks.contains { $0.id == requested } ? requested : nil }
            ?? storage.state.focusedDeskID
        self.websiteDataStore = websiteDataStore
        self.sheetNavigation = sheetNavigation
        self.preferences = preferences
        self.terminalCommandRunner = terminalCommandRunner
        self.webExtensionHost = webExtensionHost
        self.webExtensionWindow = webExtensionWindow
        self.canPresentDesk = canPresentDesk
        self.onDeskPresentationRequest = onDeskPresentationRequest
        self.onWillResetDen = onWillResetDen
        ensureFocusedObjects()
        if let restoredDrawerItemID = state.expandedDrawerItemID,
            state.drawerItems.contains(where: { $0.id == restoredDrawerItemID })
        {
            selectedDrawerItemID = restoredDrawerItemID
        }
    }

    static func normalizedPersistedState(_ state: DenState) -> DenState {
        var copy = state
        for deskIndex in copy.desks.indices {
            for boardIndex in copy.desks[deskIndex].boards.indices {
                copy.desks[deskIndex].boards[boardIndex].currentSheetURL =
                    copy.desks[deskIndex].boards[boardIndex].currentSheetURL.map(SheetURLPolicy.canonicalSheetURL)
                copy.desks[deskIndex].boards[boardIndex].firstSheetURL =
                    copy.desks[deskIndex].boards[boardIndex].firstSheetURL.map(SheetURLPolicy.canonicalSheetURL)
            }
        }
        return copy
    }

    func resetDen() {
        onWillResetDen?()
        releaseRuntimes()
        if isBoardDragging {
            boardDragCancellationRequest &+= 1
        }
        if isDeskDragging {
            deskDragCancellationRequest &+= 1
        }
        state = .sample
        presentedDeskID = state.focusedDeskID
        openBoardPanelInitialURL = nil
        openBoardPanelMessage = nil
        setTemporaryContext(nil)
        isZenViewPresented = false
        isFocusModePresented = false
        activeDrag = nil
        boardWidthPanelMessage = nil
        pendingConfirmation = nil
        maximizedBoardID = nil
        dismissDeskFilter()
        overviewSelection = nil
        overviewQuery = ""
        overviewFilterPhase = .inactive
        recentlyRemovedBoards.removeAll()
        recentlyDiscardedDrawerItems.removeAll()
        notifications.removeAll()
        isNotificationListPresented = false
        selectedNotificationID = nil
        drawerQuery = ""
        drawerFilterPhase = .inactive
        selectedDrawerItemID = nil
        toastTask?.cancel()
        toastMessage = nil
        isDenMode = false
        save()
        showToast("Reset Den completed.", style: .success)
    }

    func showToast(_ message: String, style: ToastMessage.ToastStyle = .info) {
        showToast(title: nil, body: message, style: style)
    }

    func showToast(
        title: String?,
        body: String,
        style: ToastMessage.ToastStyle = .info,
        target: ToastTarget? = nil
    ) {
        guard title?.isEmpty == false || !body.isEmpty else { return }
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            toastMessage = ToastMessage(title: title, body: body, style: style, target: target)
        }
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.toastDuration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.15)) {
                self?.toastMessage = nil
            }
        }
    }

    func handleToastTap() {
        guard let target = toastMessage?.target else {
            dismissToast()
            return
        }

        switch target {
        case .board(let boardID):
            guard boardIndices(for: boardID) != nil else {
                dismissToast()
                return
            }
            setTemporaryContext(nil)
            focusBoard(boardID, exitsDenMode: true)
        case .drawerItem(let itemID):
            focusDrawerItem(itemID)
        case .notification(let notificationID):
            guard let notification = notifications.first(where: { $0.id == notificationID }) else {
                dismissToast()
                return
            }
            markNotificationRead(notificationID)
            guard boardIndices(for: notification.boardID) != nil else {
                dismissToast()
                return
            }
            closeNotificationList()
            setTemporaryContext(nil)
            focusBoard(notification.boardID, exitsDenMode: true)
        }
        dismissToast()
    }

    func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        withAnimation(.easeIn(duration: 0.15)) {
            toastMessage = nil
        }
    }

    func requestResetDenConfirmation() {
        pendingConfirmation = .resetDen
    }

    func confirmResetDen() {
        guard isResetDenPending else { return }
        resetDen()
    }

    func cancelResetDen() {
        if isResetDenPending {
            pendingConfirmation = nil
        }
    }

    var focusedDeskIndex: Int? {
        state.desks.firstIndex { $0.id == presentedDeskID }
    }

    func boardIndices(for boardID: UUID) -> (desk: Int, board: Int)? {
        for deskIndex in state.desks.indices {
            if let boardIndex = state.desks[deskIndex].boards.firstIndex(where: { $0.id == boardID }) {
                return (deskIndex, boardIndex)
            }
        }
        return nil
    }

    @discardableResult
    func setFocusedDesk(_ deskID: UUID) -> Bool {
        guard presentedDeskID != deskID else { return false }
        guard state.desks.contains(where: { $0.id == deskID }) else { return false }
        guard onDeskPresentationRequest?(deskID) ?? true else { return false }
        previousFocusedDeskID = presentedDeskID
        presentedDeskID = deskID
        state.focusedDeskID = deskID
        return true
    }

    func canSelectDesk(_ deskID: UUID) -> Bool {
        deskID == presentedDeskID || (canPresentDesk?(deskID) ?? true)
    }

    func returnToPreviousDesk() {
        guard let previousFocusedDeskID else { return }
        guard setFocusedDesk(previousFocusedDeskID) else {
            self.previousFocusedDeskID = nil
            return
        }
        dismissDeskFilter()
        isDenMode = false
        ensureFocusedObjects()
        save()
    }

    @discardableResult
    func removeBoard(at indices: (desk: Int, board: Int), focusNext: Bool = false) -> BoardState {
        let board = state.desks[indices.desk].boards.remove(at: indices.board)
        let boards = state.desks[indices.desk].boards
        guard state.desks[indices.desk].focusedBoardID == board.id else { return board }

        let focusedBoardID: UUID?
        if focusNext && indices.board < boards.count {
            focusedBoardID = boards[indices.board].id
        } else if indices.board > 0 {
            focusedBoardID = boards[indices.board - 1].id
        } else {
            focusedBoardID = boards.first?.id
        }
        state.desks[indices.desk].focusedBoardID = focusedBoardID
        return board
    }

    func ensureFocusedObjects() {
        if state.desks.isEmpty {
            state = .sample
            presentedDeskID = state.focusedDeskID
            return
        }

        if !state.desks.contains(where: { $0.id == state.focusedDeskID }),
            let firstDeskID = state.desks.first?.id
        {
            state.focusedDeskID = firstDeskID
        }
        if !state.desks.contains(where: { $0.id == presentedDeskID }),
            let firstDeskID = state.desks.first(where: { canPresentDesk?($0.id) ?? true })?.id
                ?? state.desks.first?.id
        {
            presentedDeskID = firstDeskID
        }

        for deskIndex in state.desks.indices {
            let boards = state.desks[deskIndex].boards
            if !boards.contains(where: { $0.id == state.desks[deskIndex].focusedBoardID }) {
                state.desks[deskIndex].focusedBoardID = boards.first?.id
            }
        }
    }

    func save() {
        guard activeDrag == nil else { return }
        storage.onSave?(state)
    }

    func saveDeskPresets() {
        storage.onDeskPresetsSave?(deskPresets)
    }

    func wrappedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }

    func updateFullscreenStatus(boardID: UUID, isFullscreen: Bool) {
        if isFullscreen {
            isDenMode = false
            isFullscreenActive = true
        } else {
            let focusedBoardIDs = Set(focusedDesk?.boards.map(\.id) ?? [])
            isFullscreenActive = runtimes.contains { boardID, runtime in
                focusedBoardIDs.contains(boardID)
                    && (runtime.webView.fullscreenState == .inFullscreen
                        || runtime.webView.fullscreenState == .enteringFullscreen)
            }
        }
    }

    func setTemporaryContext(_ context: TemporaryContext?) {
        if context != nil {
            dismissDeskFilter()
            isNotificationListPresented = false
            selectedNotificationID = nil
        }
        if temporaryContext == .openBoard, context != .openBoard {
            openBoardPanelInitialURL = nil
        }
        if temporaryContext == .overview, context != .overview {
            cancelOverviewBoardDrag()
            overviewSelection = nil
            overviewQuery = ""
            overviewFilterPhase = .inactive
        }
        if temporaryContext == .boardWidth, context != .boardWidth {
            boardWidthPanelMessage = nil
        }
        if temporaryContext == .drawer, context != .drawer {
            drawerQuery = ""
            drawerFilterPhase = .inactive
        }
        if temporaryContext == .zmxDuplication, context != .zmxDuplication {
            zmxDuplicationRootSessionName = nil
        }
        temporaryContext = context
    }
}

enum TemporaryContext: Equatable {
    case essentialsPrefix
    case openBoard
    case zmxSessions
    case zmxDuplication
    case editBoardLink
    case newDesk
    case replaceDesk
    case deskPresetManagement
    case overview
    case boardActivity
    case keyboardShortcuts
    case boardWidth
    case saveDeskPreset
    case renameBoard
    case renameDesk
    case drawer
}

enum DenFilterPhase: Equatable {
    case inactive
    case filtering
    case selecting
}

enum PendingConfirmation {
    case deleteDesk(DeskState)
    case replaceDesk(PendingDeskReplacement)
    case deleteDeskPreset(PersonalDeskPreset)
    case replaceDeskPreset(PersonalDeskPreset)
    case clearDrawer(Int)
    case clearNotifications(Int)
    case resetDen
}

enum ActiveDrag: Equatable {
    case board(UUID)
    case desk(UUID)
}

struct OverviewSelection: Equatable {
    let deskID: UUID
    let boardID: UUID?
}

struct BoardLayoutMetrics: Equatable {
    let availableWidth: Double
    let spacing: Double
}

struct RecentlyRemovedBoard {
    let board: BoardState
    let sourceDeskID: UUID
    let sourceBoardIndex: Int
}

struct PendingDeskReplacement {
    let deskID: UUID
    let originalLabel: String
    let originalBoardCount: Int
    let presetLabel: String
    let label: String
    let boards: [DeskPresetBoard]
    let focusedBoardIndex: Int?
}

extension JSONEncoder {
    static var denEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
