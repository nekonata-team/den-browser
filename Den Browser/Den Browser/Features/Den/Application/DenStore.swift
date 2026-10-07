import AppKit
import DenDomain
import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class DenStore {
    static let maximumDeskCount = 10
    static let maximumRecentItemCount = 500
    static let maximumNotificationCount = 200
    static let maximumRecentlyRemovedBoardCount = 10
    static let maximumRecentlyDiscardedDrawerItemCount = 10
    static let maximumPersistedRecentInputLength = 2_048

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
    private(set) var presentedDeskID: DeskID
    private(set) var latestFeedback: DenFeedback?
    var activeDrag: ActiveDrag? {
        get { storage.activeDrag }
        set { storage.activeDrag = newValue }
    }
    var recentlyRemovedBoards: [RecentlyRemovedBoard] {
        get { storage.recentlyRemovedBoards }
        set { storage.recentlyRemovedBoards = newValue }
    }
    var recentlyDiscardedDrawerItems: [DrawerItem] {
        get { storage.recentlyDiscardedDrawerItems }
        set { storage.recentlyDiscardedDrawerItems = newValue }
    }
    var isBoardDragging: Bool {
        guard case .board? = activeDrag else { return false }
        return true
    }
    var isDeskDragging: Bool {
        guard case .desk? = activeDrag else { return false }
        return true
    }
    private(set) var activeDownloads: [DownloadActivity] = []
    let sheetNavigation: SheetNavigationManager
    let preferences: AppPreferences
    let pasteboard: NSPasteboard
    let websiteDataStore: WKWebsiteDataStore
    let profileID: ProfileID?
    let ipcSocketPath: String
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

    var webRuntimes: [BoardID: WebBoardRuntime] {
        get { storage.webRuntimes }
        set { storage.webRuntimes = newValue }
    }
    var terminalRuntimes: [BoardID: TerminalRuntime] {
        get { storage.terminalRuntimes }
        set { storage.terminalRuntimes = newValue }
    }
    @ObservationIgnored var onWindowEffect: ((DenWindowEffect) -> Void)?
    @ObservationIgnored var drawerPreviewRuntime: DrawerPreviewRuntime?
    @ObservationIgnored var zmxCommandTask: Task<Void, Never>?
    @ObservationIgnored var screenshotTask: Task<Void, Never>?
    @ObservationIgnored var previousFocusedDeskID: DeskID?
    @ObservationIgnored var anchorJumpOriginBoardIDByDesk: [DeskID: BoardID] = [:]
    @ObservationIgnored private let terminalCommandRunner: any TerminalCommandRunning
    @ObservationIgnored private let requestWebExtensionContext: (() -> (WebExtensionHost, MV3WebExtensionWindow)?)?
    @ObservationIgnored let canPresentDesk: ((DeskID) -> Bool)?
    @ObservationIgnored private let onDeskPresentationRequest: ((DeskID) -> Bool)?
    @ObservationIgnored private let onWillResetDen: (() -> Void)?
    var onRecentItemsSave: (([RecentItem]) -> Bool)? { storage.onRecentItemsSave }

    func handleExternalURL(_ url: URL) {
        switch preferences.externalLinkDestination {
        case .drawerPreview:
            keepInDrawer(url)
        case .focusedBoard:
            _ = createBoard(
                urlString: url.absoluteString,
                preferredWidth: focusedBoard?.width,
                afterBoardID: focusedBoard?.id,
                recentItem: .url(WebURLPolicy.canonicalSheetURL(url)))
        }
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
        releaseDrawerPreview()
        webExtensionHost = host
        webExtensionWindow = window
    }

    var hasWebExtensionDemand: Bool {
        !webRuntimes.isEmpty || drawerPreviewRuntime != nil
    }

    func ensureWebExtensionContext() {
        guard webExtensionHost == nil, let (host, window) = requestWebExtensionContext?() else { return }
        webExtensionHost = host
        webExtensionWindow = window
    }

    var canCreateDesk: Bool {
        state.desks.count < Self.maximumDeskCount
    }

    var canDeleteFocusedDesk: Bool {
        state.desks.count > 1
            && state.desks.contains { $0.id != presentedDeskID && (canPresentDesk?($0.id) ?? true) }
    }

    init(
        state: DenState,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        preferences: AppPreferences,
        pasteboard: NSPasteboard = .general,
        terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner(),
        webExtensionHost: WebExtensionHost? = nil,
        webExtensionWindow: MV3WebExtensionWindow? = nil,
        requestWebExtensionContext: (() -> (WebExtensionHost, MV3WebExtensionWindow)?)? = nil,
        deskPresets: [PersonalDeskPreset] = [],
        recentItems: [RecentItem] = [],
        onSave: ((DenState) -> Bool)? = nil,
        onDeskPresetsSave: (([PersonalDeskPreset]) -> Bool)? = nil,
        onRecentItemsSave: (([RecentItem]) -> Bool)? = nil,
        profileID: ProfileID? = nil,
        ipcSocketPath: String = DenSocketPath.resolve()
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
        self.profileID = profileID
        self.ipcSocketPath = ipcSocketPath
        self.sheetNavigation = sheetNavigation
        self.preferences = preferences
        self.pasteboard = pasteboard
        self.terminalCommandRunner = terminalCommandRunner
        self.requestWebExtensionContext = requestWebExtensionContext
        self.webExtensionHost = webExtensionHost
        self.webExtensionWindow = webExtensionWindow
        self.canPresentDesk = nil
        onDeskPresentationRequest = nil
        onWillResetDen = nil
        storage.drawerPresentations.add(self)
        if self.state != state {
            _ = onSave?(self.state)
        }
    }

    init(
        storage: DenStorage,
        presentedDeskID: DeskID?,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        preferences: AppPreferences,
        pasteboard: NSPasteboard = .general,
        webExtensionHost: WebExtensionHost? = nil,
        webExtensionWindow: MV3WebExtensionWindow? = nil,
        requestWebExtensionContext: (() -> (WebExtensionHost, MV3WebExtensionWindow)?)? = nil,
        canPresentDesk: @escaping (DeskID) -> Bool,
        onDeskPresentationRequest: @escaping (DeskID) -> Bool,
        onWillResetDen: @escaping () -> Void,
        terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner(),
        profileID: ProfileID? = nil,
        ipcSocketPath: String = DenSocketPath.resolve()
    ) {
        self.storage = storage
        self.presentedDeskID =
            presentedDeskID
            .flatMap { requested in storage.state.desks.contains { $0.id == requested } ? requested : nil }
            ?? storage.state.focusedDeskID
        self.websiteDataStore = websiteDataStore
        self.profileID = profileID
        self.ipcSocketPath = ipcSocketPath
        self.sheetNavigation = sheetNavigation
        self.preferences = preferences
        self.pasteboard = pasteboard
        self.terminalCommandRunner = terminalCommandRunner
        self.requestWebExtensionContext = requestWebExtensionContext
        self.webExtensionHost = webExtensionHost
        self.webExtensionWindow = webExtensionWindow
        self.canPresentDesk = canPresentDesk
        self.onDeskPresentationRequest = onDeskPresentationRequest
        self.onWillResetDen = onWillResetDen
        storage.drawerPresentations.add(self)
    }

    static func normalizedPersistedState(_ state: DenState) -> DenState {
        if state.desks.isEmpty {
            return .sample
        }
        var copy = state
        if !copy.desks.contains(where: { $0.id == copy.focusedDeskID }),
            let firstDeskID = copy.desks.first?.id
        {
            copy.focusedDeskID = firstDeskID
        }
        for deskIndex in copy.desks.indices {
            let boardCount = copy.desks[deskIndex].boards.count
            copy.desks[deskIndex].boards.removeAll(where: \.isTutorial)
            if copy.desks[deskIndex].boards.count != boardCount {
                copy.desks[deskIndex].scrollOffsetX = nil
            }
            for boardIndex in copy.desks[deskIndex].boards.indices {
                copy.desks[deskIndex].boards[boardIndex].currentSheetURL =
                    copy.desks[deskIndex].boards[boardIndex].currentSheetURL.map(WebURLPolicy.canonicalSheetURL)
                copy.desks[deskIndex].boards[boardIndex].firstSheetURL =
                    copy.desks[deskIndex].boards[boardIndex].firstSheetURL.map(WebURLPolicy.canonicalSheetURL)
            }
            let boards = copy.desks[deskIndex].boards
            if !boards.contains(where: { $0.id == copy.desks[deskIndex].focusedBoardID }) {
                copy.desks[deskIndex].focusedBoardID = boards.first?.id
            }
            if let anchorBoardID = copy.desks[deskIndex].anchorBoardID,
                !boards.contains(where: { $0.id == anchorBoardID })
            {
                copy.desks[deskIndex].anchorBoardID = nil
            }
        }
        return copy
    }

    func resetDen() {
        onWillResetDen?()
        releaseRuntimes()
        releaseWindowResources()
        if case .board? = activeDrag { onWindowEffect?(.cancelBoardDrag) }
        if case .desk? = activeDrag { onWindowEffect?(.cancelDeskDrag) }
        state = .sample
        presentedDeskID = state.focusedDeskID
        preferences.setBoardRailPresented(false)
        activeDrag = nil
        onWindowEffect?(.clearBoardInputRequests)
        recentlyRemovedBoards.removeAll()
        recentlyDiscardedDrawerItems.removeAll()
        notifications.removeAll()
        previousFocusedDeskID = nil
        anchorJumpOriginBoardIDByDesk.removeAll()
        save()
        onWindowEffect?(.resetPresentation)
        reportFeedback("Reset Den completed.", severity: .success)
    }

    @discardableResult
    func prepareBoardLinkFocus(
        _ boardID: BoardID,
        origin: BoardOperationOrigin = .interactive
    ) -> BoardLinkFocusIntent {
        let intent = BoardLinkFocusIntent(boardID: boardID, origin: origin)
        onWindowEffect?(.boardLinkFocusRequested(intent))
        return intent
    }

    @discardableResult
    func prepareBoardRemoval(origin: BoardOperationOrigin) -> BoardRemovalIntent {
        let intent = BoardRemovalIntent(origin: origin)
        onWindowEffect?(.boardRemovalRequested(intent))
        return intent
    }

    func reportFeedback(_ message: String, severity: DenFeedback.Severity = .info) {
        reportFeedback(title: nil, body: message, severity: severity)
    }

    func handleDownloadActivity(_ event: DownloadActivityEvent) {
        switch event {
        case .started(let activity):
            if let index = activeDownloads.firstIndex(where: { $0.id == activity.id }) {
                activeDownloads[index] = activity
            } else {
                activeDownloads.append(activity)
            }
        case .progressed(let id, let fractionCompleted):
            guard let index = activeDownloads.firstIndex(where: { $0.id == id }) else { return }
            activeDownloads[index].fractionCompleted = fractionCompleted
        case .ended(let id):
            activeDownloads.removeAll { $0.id == id }
        }
    }

    func reportFeedback(
        title: String?,
        body: String,
        severity: DenFeedback.Severity = .info,
        target: DenFeedback.Target? = nil
    ) {
        guard title?.isEmpty == false || !body.isEmpty else { return }
        latestFeedback = DenFeedback(title: title, body: body, severity: severity, target: target)
        onWindowEffect?(.feedback(latestFeedback))
    }

    func clearLatestNotificationFeedback() {
        guard let target = latestFeedback?.target, case .notification = target else { return }
        latestFeedback = nil
        onWindowEffect?(.feedback(nil))
    }

    func openFeedbackTarget(_ target: DenFeedback.Target?) {
        guard let target else { return }
        switch target {
        case .board(let boardID):
            guard boardIndices(for: boardID) != nil else { return }
            onWindowEffect?(.dismissTemporaryPresentation)
            onWindowEffect?(.exitDenMode)
            focusBoard(boardID, exitsDenMode: true)
        case .drawerItem(let itemID):
            onWindowEffect?(.openDrawerItem(itemID))
        case .notification(let notificationID):
            guard let notification = notifications.first(where: { $0.id == notificationID }) else {
                return
            }
            markNotificationRead(notificationID)
            guard boardIndices(for: notification.boardID) != nil else { return }
            onWindowEffect?(.dismissTemporaryPresentation)
            onWindowEffect?(.exitDenMode)
            focusBoard(notification.boardID, exitsDenMode: true)
        }
    }

    var focusedDeskIndex: Int? {
        state.desks.firstIndex { $0.id == presentedDeskID }
    }

    func boardIndices(for boardID: BoardID) -> (desk: Int, board: Int)? {
        for deskIndex in state.desks.indices {
            if let boardIndex = state.desks[deskIndex].boards.firstIndex(where: { $0.id == boardID }) {
                return (deskIndex, boardIndex)
            }
        }
        return nil
    }

    func board(for boardID: BoardID) -> BoardState? {
        guard let indices = boardIndices(for: boardID) else { return nil }
        return state.desks[indices.desk].boards[indices.board]
    }

    @discardableResult
    func setFocusedDesk(_ deskID: DeskID, autoPIP: Bool = true) -> Bool {
        guard presentedDeskID != deskID else { return false }
        guard state.desks.contains(where: { $0.id == deskID }) else { return false }
        guard onDeskPresentationRequest?(deskID) ?? true else { return false }
        if autoPIP {
            enterPictureInPictureForDeskSwitch()
        }
        previousFocusedDeskID = presentedDeskID
        presentedDeskID = deskID
        state.focusedDeskID = deskID
        onWindowEffect?(.clearBoardInputRequests)
        if let boardID = focusedDesk?.focusedBoardID {
            markNotificationsRead(for: boardID)
        }
        return true
    }

    private func enterPictureInPictureForDeskSwitch() {
        guard
            preferences.automaticPIPOnDeskSwitch,
            let focusedDesk,
            let focusedBoardID = focusedDesk.focusedBoardID,
            let runtime = webRuntimes[focusedBoardID]
        else { return }

        runtime.enterPictureInPictureIfPlaying()
    }

    func canSelectDesk(_ deskID: DeskID) -> Bool {
        deskID == presentedDeskID || (canPresentDesk?(deskID) ?? true)
    }

    func returnToPreviousDesk() {
        guard let previousFocusedDeskID else { return }
        guard setFocusedDesk(previousFocusedDeskID) else {
            self.previousFocusedDeskID = nil
            return
        }
        onWindowEffect?(.exitDenMode)
        saveDeferredState()
    }

    @discardableResult
    func removeBoard(at indices: (desk: Int, board: Int), focusNext: Bool = false) -> BoardState {
        let board = state.desks[indices.desk].boards.remove(at: indices.board)
        let deskID = state.desks[indices.desk].id
        if state.desks[indices.desk].anchorBoardID == board.id {
            state.desks[indices.desk].anchorBoardID = nil
            anchorJumpOriginBoardIDByDesk.removeValue(forKey: deskID)
        } else if anchorJumpOriginBoardIDByDesk[deskID] == board.id {
            anchorJumpOriginBoardIDByDesk.removeValue(forKey: deskID)
        }
        let boards = state.desks[indices.desk].boards
        if boards.isEmpty {
            state.desks[indices.desk].scrollOffsetX = nil
        }
        guard state.desks[indices.desk].focusedBoardID == board.id else { return board }

        let focusedBoardID: BoardID?
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

    @discardableResult
    func save() -> Bool {
        let signpost = PerformanceTrace.beginInterval("DenStore.save")
        defer { PerformanceTrace.endInterval("DenStore.save", signpost) }
        guard activeDrag == nil else { return false }
        return storage.onSave?(Self.normalizedPersistedState(state)) ?? false
    }

    func saveDeferredState() {
        guard activeDrag == nil else { return }
        if let onDeferredSave = storage.onDeferredSave {
            onDeferredSave()
        } else {
            _ = save()
        }
    }

    @discardableResult
    func saveStateAndRecentItems() -> Bool {
        if storage.onSave != nil {
            return save()
        }
        return storage.onRecentItemsSave?(recentItems) ?? true
    }

    @discardableResult
    func saveDeskPresets() -> Bool {
        storage.onDeskPresetsSave?(deskPresets) ?? false
    }

    func wrappedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }

    func updateFullscreenStatus(boardID: BoardID, isFullscreen: Bool) {
        if isFullscreen {
            onWindowEffect?(.exitDenMode)
            onWindowEffect?(.fullscreenChanged(true))
        } else {
            let focusedBoardIDs = Set(focusedDesk?.boards.map(\.id) ?? [])
            let isFullscreenActive = webRuntimes.contains { boardID, runtime in
                focusedBoardIDs.contains(boardID)
                    && (runtime.webView.fullscreenState == .inFullscreen
                        || runtime.webView.fullscreenState == .enteringFullscreen)
            }
            onWindowEffect?(.fullscreenChanged(isFullscreenActive))
        }
    }

    func invalidateReferences(toRemovedBoardIDs removedBoardIDs: Set<BoardID>) {
        for presentation in storage.drawerPresentations.allObjects {
            presentation.anchorJumpOriginBoardIDByDesk = presentation.anchorJumpOriginBoardIDByDesk
                .filter { !removedBoardIDs.contains($0.value) }
            for boardID in removedBoardIDs {
                presentation.onWindowEffect?(.boardRemoved(boardID))
            }
        }
        if case .board(let boardID) = activeDrag, removedBoardIDs.contains(boardID) {
            activeDrag = nil
        }
    }

    func invalidateReferences(toRemovedDeskID removedDeskID: DeskID) {
        for presentation in storage.drawerPresentations.allObjects {
            if presentation.previousFocusedDeskID == removedDeskID {
                presentation.previousFocusedDeskID = nil
            }
            presentation.anchorJumpOriginBoardIDByDesk.removeValue(forKey: removedDeskID)
            presentation.onWindowEffect?(.deskRemoved(removedDeskID))
        }
        if case .desk(let deskID) = activeDrag, deskID == removedDeskID {
            activeDrag = nil
        }
    }

}
