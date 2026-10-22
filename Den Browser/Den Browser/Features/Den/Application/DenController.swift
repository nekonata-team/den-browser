import AppKit
import DenApplication
import DenDomain
import DenInfrastructure
import DenPresentationModels
import Foundation
import Observation
import WebKit

struct BoardIndices {
    let desk: DeskIndex
    let board: BoardIndex

    var deskOffset: Int { desk.rawValue }
    var boardOffset: Int { board.rawValue }
}

@MainActor
@Observable
final class DenController {
    static let maximumDeskCount = DeskCreation.maximumDeskCount
    static let maximumRecentItemCount = BoardCreation.maximumRecentItemCount
    static let maximumRecentlyRemovedBoardCount = BoardRemoval.maximumHistoryCount

    let storage: DenProfileResources
    var state: DenState { storage.state }
    var deskPresets: [PersonalDeskPreset] { storage.deskPresets }
    var recentItems: [RecentItem] { storage.recentItems }
    var notifications: [DenNotification] { storage.notifications }
    var unreadNotificationCount: Int {
        storage.notificationOperations.unreadCount()
    }
    var essentials: [Essential] { preferences.essentials }
    private(set) var presentedDeskID: DeskID
    private(set) var latestFeedback: DenFeedback?
    var activeDrag: ActiveDrag? { storage.activeDrag }
    var recentlyRemovedBoards: [RecentlyRemovedBoard] { storage.recentlyRemovedBoards }
    var recentlyDiscardedDrawerItems: [DrawerItem] { storage.recentlyDiscardedDrawerItems }
    var isBoardDragging: Bool {
        guard case .board? = activeDrag else { return false }
        return true
    }
    var isDeskDragging: Bool {
        guard case .desk? = activeDrag else { return false }
        return true
    }
    var canCaptureFacing: Bool {
        activeDrag == nil
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

    var webRuntimes: [BoardID: WebRuntime] {
        get { storage.webRuntimes }
        set { storage.webRuntimes = newValue }
    }
    var terminalRuntimes: [BoardID: TerminalRuntime] {
        get { storage.terminalRuntimes }
        set { storage.terminalRuntimes = newValue }
    }
    var facingCache: BoardFacingCache { storage.facingCache }
    var facingCapture: BoardFacingCapture { storage.facingCapture }
    var presetFacingStore: PresetFacingStore { storage.presetFacingStore }

    func savePresetFacings(for presetID: UUID, boards: [BoardState]) {
        for (index, board) in boards.enumerated() {
            if let image = facingCache.image(for: board.id) {
                presetFacingStore.setFacing(image, for: presetID, at: index)
            }
        }
    }

    func captureFocusedDeskFacings() async {
        guard canCaptureFacing, let boards = focusedDesk?.boards else { return }
        for board in boards {
            if let runtime = webRuntimes[board.id], !runtime.webView.isHidden {
                await facingCapture.captureWeb(boardID: board.id, webView: runtime.webView)
            } else if let runtime = terminalRuntimes[board.id], !runtime.terminalView.isHidden {
                facingCapture.captureTerminal(boardID: board.id, terminalView: runtime.terminalView)
            }
            await facingCache.loadFacing(for: board.id)
        }
    }

    func removePresetFacings(for presetID: UUID) {
        presetFacingStore.remove(for: presetID)
    }

    let inputSourceTracker = BoardInputSourceTracker()
    @ObservationIgnored var onWindowEffect: ((DenWindowEffect) -> Void)?
    @ObservationIgnored private let windowResources = DenWindowResources()
    var drawerPeekRuntime: WebRuntime? {
        get { windowResources.drawerPeek }
        set { windowResources.drawerPeek = newValue }
    }
    var zmxCommandTask: Task<Void, Never>? {
        get { windowResources.zmxCommandTask }
        set { windowResources.zmxCommandTask = newValue }
    }
    func startScreenshotOperation(_ operation: @escaping @MainActor () async -> Void) {
        windowResources.startScreenshotOperation(operation)
    }
    @ObservationIgnored var previousFocusedDeskID: DeskID?
    @ObservationIgnored var anchorJumpOriginBoardIDByDesk: [DeskID: BoardID] = [:]
    @ObservationIgnored private let terminalCommandRunner: any TerminalCommandRunning
    @ObservationIgnored private let requestWebExtensionContext: (() -> (WebExtensionHost, MV3WebExtensionWindow)?)?
    @ObservationIgnored let canPresentDesk: ((DeskID) -> Bool)?
    @ObservationIgnored private let onDeskPresentationRequest: ((DeskID) -> Bool)?
    @ObservationIgnored private let onWillResetDen: (() -> Void)?
    var onRecentItemsSave: (([RecentItem]) -> Bool)? { storage.onRecentItemsSave }

    func cancelWindowOperationTasks() {
        windowResources.cancelTasks()
    }

    func handleExternalURL(_ url: URL) {
        switch preferences.externalLinkDestination {
        case .drawerPeek:
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
        return state.desks[deskIndex.rawValue].boards[boardIndex.rawValue]
    }

    func updateWebExtensionHost(
        _ host: WebExtensionHost?,
        window: MV3WebExtensionWindow?
    ) {
        guard webExtensionHost !== host || webExtensionWindow !== window else { return }
        releaseWebRuntimes()
        releaseDrawerPeek()
        webExtensionHost = host
        webExtensionWindow = window
    }

    var hasWebExtensionDemand: Bool {
        !webRuntimes.isEmpty || drawerPeekRuntime != nil
    }

    func ensureWebExtensionContext() {
        guard webExtensionHost == nil, let (host, window) = requestWebExtensionContext?() else { return }
        webExtensionHost = host
        webExtensionWindow = window
    }

    var canCreateDesk: Bool {
        storage.deskLifecycle.canCreate
    }

    var canDeleteFocusedDesk: Bool {
        storage.deskLifecycle.canDelete(presentedDeskID, isAvailable: { canPresentDesk?($0) ?? true })
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
        let storage = DenProfileResources(
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
        inputSourceTracker.isEnabled = { [weak self] in
            self?.preferences.rememberBoardInputMethod ?? false
        }
        if self.state != state {
            _ = onSave?(self.state)
        }
    }

    init(
        storage: DenProfileResources,
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
        inputSourceTracker.isEnabled = { [weak self] in
            self?.preferences.rememberBoardInputMethod ?? false
        }
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
        storage.denReset.perform { notice in
            switch notice {
            case .prepare:
                onWillResetDen?()
                releaseRuntimes()
                releaseWindowResources()
            case .cancelDrag(.board):
                onWindowEffect?(.cancelBoardDrag)
            case .cancelDrag(.desk):
                onWindowEffect?(.cancelDeskDrag)
            case .stateReplaced(let deskID):
                presentedDeskID = deskID
                preferences.setBoardRailPresented(false)
            case .clearInputRequests:
                onWindowEffect?(.clearBoardInputRequests)
            case .clearWindowReferences:
                previousFocusedDeskID = nil
                anchorJumpOriginBoardIDByDesk.removeAll()
            case .finished:
                onWindowEffect?(.resetPresentation)
                reportFeedback("Reset Den completed.", severity: .success)
            }
        }
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
            if focusedDesk?.focusedBoardID == boardID { centerFocusedBoard() }
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
            if focusedDesk?.focusedBoardID == notification.boardID { centerFocusedBoard() }
        }
    }

    var focusedDeskIndex: DeskIndex? {
        state.desks.firstIndex { $0.id == presentedDeskID }.map { DeskIndex(rawValue: $0) }
    }

    func boardIndices(for boardID: BoardID) -> BoardIndices? {
        for deskIndex in state.desks.indices {
            if let boardIndex = state.desks[deskIndex].boards.firstIndex(where: { $0.id == boardID }) {
                return BoardIndices(
                    desk: DeskIndex(rawValue: deskIndex),
                    board: BoardIndex(rawValue: boardIndex))
            }
        }
        return nil
    }

    func board(for boardID: BoardID) -> BoardState? {
        guard let indices = boardIndices(for: boardID) else { return nil }
        return state.desks[indices.deskOffset].boards[indices.boardOffset]
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
        storage.deskUpdates.recordPresentedDesk(deskID)
        onWindowEffect?(.clearBoardInputRequests)
        if let boardID = focusedDesk?.focusedBoardID {
            inputSourceTracker.boardDidFocus(boardID, isEnabled: preferences.rememberBoardInputMethod)
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
    func save() -> Bool {
        let signpost = PerformanceTrace.beginInterval("DenController.save")
        defer { PerformanceTrace.endInterval("DenController.save", signpost) }
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
            storage.activeDrag = nil
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
            storage.activeDrag = nil
        }
    }
}
