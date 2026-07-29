import Foundation
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class DenStore {
    static let maximumDeskCount = 10
    static let maximumRecentItemCount = 100
    static let maximumPersistedRecentInputLength = 2_048

    var state: DenState
    var deskPresets: [PersonalDeskPreset]
    var recentItems: [RecentItem]
    private(set) var temporaryContext: TemporaryContext?
    var isZenViewPresented = false
    var isDenMode = false
    var isFullscreenActive = false
    var deskFilterPhase: DeskFilterPhase = .inactive
    var deskFilterQuery = ""
    var deskFilterSelectionBoardID: UUID?
    var overviewQuery = ""
    var isOverviewFilterMode = false
    var boardWidthPanelMessage: String?
    var openBoardPanelInitialURL: URL?
    var pendingConfirmation: PendingConfirmation?
    var maximizedBoardID: UUID?
    var centerFocusedBoardRequest = 0
    var activeDrag: ActiveDrag?
    var boardDragCancellationRequest = 0
    var deskDragCancellationRequest = 0
    var overviewSelection: OverviewSelection?
    var recentlyRemovedBoard: RecentlyRemovedBoard?
    var isDrawerOpen: Bool { temporaryContext == .drawer }
    var isDeskFilterPresented: Bool { deskFilterPhase != .inactive }
    var isDeskFilterInputActive: Bool { deskFilterPhase == .filtering }
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
    var isDrawerFilterMode = false
    var selectedDrawerItemID: UUID?
    var expandedDrawerItemID: UUID? { state.expandedDrawerItemID }
    private(set) var toastMessage: ToastMessage?
    let sheetNavigation: SheetNavigationManager
    let preferences: AppPreferences
    let websiteDataStore: WKWebsiteDataStore

    @ObservationIgnored var runtimes: [UUID: BoardRuntime] = [:]
    @ObservationIgnored var drawerPreviewRuntime: DrawerPreviewRuntime?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private let onSave: ((DenState) -> Void)?
    @ObservationIgnored private let onDeskPresetsSave: (([PersonalDeskPreset]) -> Void)?
    @ObservationIgnored let onRecentItemsSave: (([RecentItem]) -> Bool)?
    var boardLayoutMetrics: BoardLayoutMetrics?

    var focusedDesk: DeskState? {
        state.desks.first { $0.id == state.focusedDeskID }
    }

    var focusedBoard: BoardState? {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return nil }
        return state.desks[deskIndex].boards[boardIndex]
    }

    var canCreateDesk: Bool {
        state.desks.count < Self.maximumDeskCount
    }

    var canDeleteFocusedDesk: Bool {
        state.desks.count > 1
    }

    var isOpenBoardPanelPresented: Bool { temporaryContext == .openBoard }
    var isNewDeskPanelPresented: Bool {
        temporaryContext == .newDesk
            || temporaryContext == .replaceDesk
            || temporaryContext == .deskPresetManagement
    }
    var isReplaceDeskPanelPresented: Bool { temporaryContext == .replaceDesk }
    var isDeskPresetManagementPresented: Bool { temporaryContext == .deskPresetManagement }
    var isOverviewPresented: Bool { temporaryContext == .overview }
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
    var isResetDenPending: Bool {
        guard case .resetDen? = pendingConfirmation else { return false }
        return true
    }
    var hasPendingConfirmation: Bool { pendingConfirmation != nil }

    convenience init() {
        self.init(state: .sample)
    }

    convenience init(state: DenState) {
        self.init(state: state, sheetNavigation: SheetNavigationManager())
    }

    convenience init(
        state: DenState,
        sheetNavigation: SheetNavigationManager,
        preferences: AppPreferences = AppPreferences()
    ) {
        self.init(
            state: state,
            websiteDataStore: .default(),
            sheetNavigation: sheetNavigation,
            preferences: preferences,
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
        deskPresets: [PersonalDeskPreset] = [],
        recentItems: [RecentItem] = [],
        onSave: ((DenState) -> Void)?,
        onDeskPresetsSave: (([PersonalDeskPreset]) -> Void)? = nil,
        onRecentItemsSave: (([RecentItem]) -> Bool)? = nil
    ) {
        self.state = state
        self.deskPresets = deskPresets
        self.recentItems = recentItems
        self.websiteDataStore = websiteDataStore
        self.sheetNavigation = sheetNavigation
        self.preferences = preferences
        self.onSave = onSave
        self.onDeskPresetsSave = onDeskPresetsSave
        self.onRecentItemsSave = onRecentItemsSave
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

    func resetDen() {
        releaseRuntimes()
        if isBoardDragging {
            boardDragCancellationRequest &+= 1
        }
        if isDeskDragging {
            deskDragCancellationRequest &+= 1
        }
        state = .sample
        openBoardPanelInitialURL = nil
        setTemporaryContext(nil)
        isZenViewPresented = false
        activeDrag = nil
        boardWidthPanelMessage = nil
        pendingConfirmation = nil
        maximizedBoardID = nil
        dismissDeskFilter()
        overviewSelection = nil
        recentlyRemovedBoard = nil
        drawerQuery = ""
        isDrawerFilterMode = false
        selectedDrawerItemID = nil
        toastTask?.cancel()
        toastMessage = nil
        isDenMode = false
        save()
        showToast("Reset Den completed.", style: .success)
    }

    func showToast(_ message: String, style: ToastMessage.ToastStyle = .info) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            toastMessage = ToastMessage(message: message, style: style)
        }
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.15)) {
                self?.toastMessage = nil
            }
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
        state.desks.firstIndex { $0.id == state.focusedDeskID }
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
    func removeBoard(at indices: (desk: Int, board: Int)) -> BoardState {
        let board = state.desks[indices.desk].boards.remove(at: indices.board)
        let boards = state.desks[indices.desk].boards
        guard state.desks[indices.desk].focusedBoardID == board.id else { return board }

        state.desks[indices.desk].focusedBoardID =
            indices.board > 0
            ? boards[indices.board - 1].id
            : boards.first?.id
        return board
    }

    func ensureFocusedObjects() {
        if state.desks.isEmpty {
            state = .sample
            return
        }

        if !state.desks.contains(where: { $0.id == state.focusedDeskID }),
            let firstDeskID = state.desks.first?.id
        {
            state.focusedDeskID = firstDeskID
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
        onSave?(state)
    }

    func saveDeskPresets() {
        onDeskPresetsSave?(deskPresets)
    }

    func wrappedIndex(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }

    func updateFullscreenStatus(boardID: UUID, isFullscreen: Bool) {
        if isFullscreen {
            isDenMode = false
            isFullscreenActive = true
        } else {
            isFullscreenActive = runtimes.values.contains {
                $0.webView.fullscreenState == .inFullscreen
                    || $0.webView.fullscreenState == .enteringFullscreen
            }
        }
    }

    func setTemporaryContext(_ context: TemporaryContext?) {
        if context != nil {
            dismissDeskFilter()
        }
        if temporaryContext == .openBoard, context != .openBoard {
            openBoardPanelInitialURL = nil
        }
        if temporaryContext == .overview, context != .overview {
            overviewSelection = nil
        }
        if temporaryContext == .boardWidth, context != .boardWidth {
            boardWidthPanelMessage = nil
        }
        if temporaryContext == .drawer, context != .drawer {
            drawerQuery = ""
            isDrawerFilterMode = false
        }
        temporaryContext = context
    }
}

enum TemporaryContext: Equatable {
    case openBoard
    case editBoardLink
    case newDesk
    case replaceDesk
    case deskPresetManagement
    case overview
    case keyboardShortcuts
    case boardWidth
    case saveDeskPreset
    case renameBoard
    case renameDesk
    case drawer
}

enum DeskFilterPhase: Equatable {
    case inactive
    case filtering
    case selecting
}

enum PendingConfirmation {
    case deleteDesk(DeskState)
    case replaceDesk(PendingDeskReplacement)
    case deleteDeskPreset(PersonalDeskPreset)
    case replaceDeskPreset(PersonalDeskPreset)
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
