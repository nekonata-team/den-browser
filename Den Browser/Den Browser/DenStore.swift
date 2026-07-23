import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class DenStore {
    static let maximumDeskCount = 10

    var state: DenState
    var deskPresets: [PersonalDeskPreset]
    private(set) var temporaryContext: TemporaryContext?
    var isZenViewPresented = false
    var isDenMode = false
    var isFullscreenActive = false
    var overviewQuery = ""
    var isOverviewFilterMode = false
    var boardWidthPanelMessage: String?
    var deskPendingDeletion: DeskState?
    var deskPresetPendingDeletion: PersonalDeskPreset?
    var deskPresetPendingReplacement: PersonalDeskPreset?
    private(set) var isResetDenPending = false
    var maximizedBoardID: UUID?
    var centerFocusedBoardRequest = 0
    var isBoardDragging = false
    var boardDragCancellationRequest = 0
    var isDeskDragging = false
    var deskDragCancellationRequest = 0
    var overviewSelectionDeskID: UUID?
    var overviewSelectionBoardID: UUID?
    var recentlyRemovedBoard: RecentlyRemovedBoard?
    let sheetNavigation: SheetNavigationManager
    let websiteDataStore: WKWebsiteDataStore

    @ObservationIgnored var runtimes: [UUID: BoardRuntime] = [:]
    @ObservationIgnored private let onSave: ((DenState) -> Void)?
    @ObservationIgnored private let onDeskPresetsSave: (([PersonalDeskPreset]) -> Void)?
    var availableBoardWidth = 0.0
    var boardSpacing = 0.0

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
        temporaryContext == .newDesk || temporaryContext == .deskPresetManagement
    }
    var isDeskPresetManagementPresented: Bool { temporaryContext == .deskPresetManagement }
    var isOverviewPresented: Bool { temporaryContext == .overview }
    var isKeyboardShortcutsPresented: Bool { temporaryContext == .keyboardShortcuts }
    var isBoardWidthPanelPresented: Bool { temporaryContext == .boardWidth }
    var isSaveDeskPresetPanelPresented: Bool { temporaryContext == .saveDeskPreset }
    var hasPendingConfirmation: Bool {
        deskPendingDeletion != nil
            || deskPresetPendingDeletion != nil
            || deskPresetPendingReplacement != nil
            || isResetDenPending
    }

    convenience init() {
        self.init(state: .sample)
    }

    convenience init(state: DenState) {
        self.init(state: state, sheetNavigation: SheetNavigationManager())
    }

    convenience init(state: DenState, sheetNavigation: SheetNavigationManager) {
        self.init(
            state: state,
            websiteDataStore: .default(),
            sheetNavigation: sheetNavigation,
            deskPresets: [],
            onSave: nil
        )
    }

    convenience init(state: DenState, onSave: @escaping (DenState) -> Void) {
        self.init(
            state: state,
            websiteDataStore: .default(),
            sheetNavigation: SheetNavigationManager(),
            deskPresets: [],
            onSave: onSave
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
            deskPresets: deskPresets,
            onSave: nil,
            onDeskPresetsSave: onDeskPresetsSave
        )
    }

    init(
        state: DenState,
        websiteDataStore: WKWebsiteDataStore,
        sheetNavigation: SheetNavigationManager,
        deskPresets: [PersonalDeskPreset] = [],
        onSave: ((DenState) -> Void)?,
        onDeskPresetsSave: (([PersonalDeskPreset]) -> Void)? = nil
    ) {
        self.state = state
        self.deskPresets = deskPresets
        self.websiteDataStore = websiteDataStore
        self.sheetNavigation = sheetNavigation
        self.onSave = onSave
        self.onDeskPresetsSave = onDeskPresetsSave
        ensureFocusedObjects()
        if self.state != state {
            onSave?(self.state)
        }
    }

    func resetDen() {
        for runtime in runtimes.values {
            sheetNavigation.didClose(runtime.webView)
        }
        runtimes.removeAll()
        if isBoardDragging {
            boardDragCancellationRequest &+= 1
        }
        if isDeskDragging {
            deskDragCancellationRequest &+= 1
        }
        state = .sample
        setTemporaryContext(nil)
        isZenViewPresented = false
        isBoardDragging = false
        isDeskDragging = false
        boardWidthPanelMessage = nil
        deskPendingDeletion = nil
        deskPresetPendingDeletion = nil
        deskPresetPendingReplacement = nil
        isResetDenPending = false
        maximizedBoardID = nil
        overviewSelectionDeskID = nil
        overviewSelectionBoardID = nil
        recentlyRemovedBoard = nil
        isDenMode = false
        save()
    }

    func requestResetDenConfirmation() {
        isResetDenPending = true
    }

    func confirmResetDen() {
        guard isResetDenPending else { return }
        resetDen()
    }

    func cancelResetDen() {
        isResetDenPending = false
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
        guard !isBoardDragging, !isDeskDragging else { return }
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
        if temporaryContext == .overview, context != .overview {
            overviewSelectionDeskID = nil
            overviewSelectionBoardID = nil
        }
        if temporaryContext == .boardWidth, context != .boardWidth {
            boardWidthPanelMessage = nil
        }
        temporaryContext = context
    }
}

enum TemporaryContext: Equatable {
    case openBoard
    case editBoardLink
    case newDesk
    case deskPresetManagement
    case overview
    case keyboardShortcuts
    case boardWidth
    case saveDeskPreset
    case renameBoard
    case renameDesk
}

struct RecentlyRemovedBoard {
    let board: BoardState
    let sourceDeskID: UUID
    let sourceBoardIndex: Int
}

extension JSONEncoder {
    static var denEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
