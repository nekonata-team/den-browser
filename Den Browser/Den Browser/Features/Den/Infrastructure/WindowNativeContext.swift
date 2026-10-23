import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation

@MainActor
struct WindowNavigationBindings {
    let readPresentedDesk: () -> DeskID
    let readPreviousDesk: () -> DeskID?
    let writePreviousDesk: (DeskID?) -> Void
    let readAnchorOrigins: () -> [DeskID: BoardID]
    let writeAnchorOrigins: ([DeskID: BoardID]) -> Void
    let present: (DeskID) -> Void
    let replacePresentedDesk: (DeskID) -> Void
    let clearHistory: () -> Void

    var presentedDeskID: DeskID { readPresentedDesk() }
    var previousFocusedDeskID: DeskID? {
        get { readPreviousDesk() }
        nonmutating set { writePreviousDesk(newValue) }
    }
    var anchorJumpOriginBoardIDByDesk: [DeskID: BoardID] {
        get { readAnchorOrigins() }
        nonmutating set { writeAnchorOrigins(newValue) }
    }
}

@MainActor
final class WindowFeedbackOutput {
    private let publishValue: (String?, String, DenFeedback.Severity, DenFeedback.Target?) -> DenFeedback?
    private let clearNotificationValue: () -> Bool
    private let emit: (DenWindowEffect) -> Void

    init(
        publish: @escaping (String?, String, DenFeedback.Severity, DenFeedback.Target?) -> DenFeedback?,
        clearNotification: @escaping () -> Bool,
        emit: @escaping (DenWindowEffect) -> Void
    ) {
        publishValue = publish
        clearNotificationValue = clearNotification
        self.emit = emit
    }

    func publish(_ message: String, severity: DenFeedback.Severity = .info) {
        publish(title: nil, body: message, severity: severity)
    }

    func publish(
        title: String?, body: String, severity: DenFeedback.Severity = .info,
        target: DenFeedback.Target? = nil
    ) {
        guard let feedback = publishValue(title, body, severity, target) else { return }
        emit(.feedback(feedback))
    }

    func clearNotification() {
        guard clearNotificationValue() else { return }
        emit(.feedback(nil))
    }
}

@MainActor
final class WindowNativeContext {
    let storage: DenProfileResources
    let configuration: BoardRuntimeConfiguration
    let windowResources: DenWindowResources
    let connection: RuntimeWindowConnection
    let runtimes: BoardRuntimeAccess
    let navigation: WindowNavigationBindings
    let feedback: WindowFeedbackOutput
    let pasteboard: NSPasteboard
    let inputSourceTracker: BoardInputSourceTracker
    let essentialEditing: EssentialEditing
    let canPresentDesk: ((DeskID) -> Bool)?
    let onDeskPresentationRequest: ((DeskID) -> Bool)?
    let onWillResetDen: (() -> Void)?

    init(
        storage: DenProfileResources, configuration: BoardRuntimeConfiguration,
        windowResources: DenWindowResources, connection: RuntimeWindowConnection,
        runtimes: BoardRuntimeAccess, navigation: WindowNavigationBindings,
        feedback: WindowFeedbackOutput, pasteboard: NSPasteboard, inputSourceTracker: BoardInputSourceTracker,
        canPresentDesk: ((DeskID) -> Bool)?, onDeskPresentationRequest: ((DeskID) -> Bool)?,
        onWillResetDen: (() -> Void)?
    ) {
        self.storage = storage
        self.configuration = configuration
        self.windowResources = windowResources
        self.connection = connection
        self.runtimes = runtimes
        self.navigation = navigation
        self.feedback = feedback
        self.pasteboard = pasteboard
        self.inputSourceTracker = inputSourceTracker
        self.canPresentDesk = canPresentDesk
        self.onDeskPresentationRequest = onDeskPresentationRequest
        self.onWillResetDen = onWillResetDen
        let preferences = configuration.preferences
        essentialEditing = EssentialEditing(
            read: { preferences.essentials }, persist: { preferences.setEssentials($0) })
    }

    var canCaptureFacing: Bool { storage.activeDrag == nil }
    var isBoardDragging: Bool {
        guard case .board? = storage.activeDrag else { return false }
        return true
    }
    var isDeskDragging: Bool {
        guard case .desk? = storage.activeDrag else { return false }
        return true
    }
    var canDeleteFocusedDesk: Bool {
        storage.deskLifecycle.canDelete(navigation.presentedDeskID, isAvailable: { canPresentDesk?($0) ?? true })
    }

    var focusedDesk: DeskState? {
        storage.data.snapshot.den.desks.first { $0.id == navigation.presentedDeskID }
    }

    var focusedBoard: BoardState? {
        guard let desk = focusedDesk else { return nil }
        return desk.boards.first { $0.id == desk.focusedBoardID }
    }

    var focusedDeskIndex: DeskIndex? {
        storage.data.snapshot.den.desks.firstIndex { $0.id == navigation.presentedDeskID }
            .map { DeskIndex(rawValue: $0) }
    }

    func boardIndices(for id: BoardID) -> BoardIndices? {
        storage.data.snapshot.den.boardIndices(for: id)
    }

    func board(for id: BoardID) -> BoardState? {
        storage.data.snapshot.den.board(for: id)
    }

    var zmxClient: ZmxClient {
        ZmxClient(
            executablePath: configuration.preferences.zmxPath,
            commandRunner: configuration.terminalCommandRunner)
    }

    var zellijClient: ZellijClient {
        ZellijClient(executablePath: configuration.preferences.zellijPath)
    }
}
