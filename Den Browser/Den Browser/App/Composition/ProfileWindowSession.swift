import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation
import Observation

@MainActor
@Observable
final class ProfileWindowSession {
    let resources: DenProfileResources
    let configuration: BoardRuntimeConfiguration
    let pasteboard: NSPasteboard
    let windowResources: DenWindowResources
    let connection: RuntimeWindowConnection
    let inputSourceTracker: BoardInputSourceTracker
    let navigation: WindowNavigationModel
    let feedback: FeedbackModel
    let downloads: DownloadActivityModel
    let context: WindowNativeContext
    let runtimes: BoardRuntimeAccess
    let boardNavigation: BoardNavigation
    let boardRemoval: BoardRemovalPresentation
    let boardOpening: BoardOpeningActions
    let desks: DeskActions
    let presets: DeskPresetActionsAdapter
    let deskLinks: DeskLinkActions
    let drawer: DrawerActions
    let input: InputOpeningActions
    let essentials: EssentialActions
    let notifications: NotificationDelivery
    let zmx: ZmxBoardActions
    let sideBoards: SideBoardCreation
    let screenshots: BoardScreenshots
    let facings: DeskFacings
    let reset: DenResetActions

    init(
        resources: DenProfileResources, configuration: BoardRuntimeConfiguration, pasteboard: NSPasteboard? = nil,
        presentedDeskID: DeskID? = nil,
        webExtensionHost: WebExtensionHost? = nil, webExtensionWindow: MV3WebExtensionWindow? = nil,
        canPresentDesk: ((DeskID) -> Bool)? = nil,
        onDeskPresentationRequest: ((DeskID) -> Bool)? = nil, onWillResetDen: (() -> Void)? = nil
    ) {
        let windowPasteboard = pasteboard ?? configuration.sheetNavigation.pasteboard
        let selectedDeskID =
            presentedDeskID.flatMap { id in
                resources.state.desks.contains { $0.id == id } ? id : nil
            } ?? resources.state.focusedDeskID
        let navigation = WindowNavigationModel(state: resources.data, presentedDeskID: selectedDeskID)
        let feedback = FeedbackModel()
        let downloads = DownloadActivityModel()
        let windowResources = DenWindowResources()
        let connection = RuntimeWindowConnection()
        let inputSourceTracker = BoardInputSourceTracker()
        let preferences = configuration.preferences
        inputSourceTracker.isEnabled = { [weak preferences] in preferences?.rememberBoardInputMethod ?? false }
        let runtimes = BoardRuntimeAccess(
            storage: resources, windowResources: windowResources, connection: connection, configuration: configuration,
            webExtensionHost: webExtensionHost, webExtensionWindow: webExtensionWindow,
            focusedDesk: { [weak navigation] in navigation?.focusedDesk })
        let output = WindowFeedbackOutput(
            publish: { feedback.publish(title: $0, body: $1, severity: $2, target: $3) },
            clearNotification: { feedback.clearNotification() },
            emit: { [weak connection] in connection?.onWindowEffect?($0) })
        let context = WindowNativeContext(
            storage: resources, configuration: configuration, windowResources: windowResources,
            connection: connection, runtimes: runtimes,
            navigation: WindowNavigationBindings(
                readPresentedDesk: { navigation.presentedDeskID },
                readPreviousDesk: { navigation.previousFocusedDeskID },
                writePreviousDesk: { navigation.previousFocusedDeskID = $0 },
                readAnchorOrigins: { navigation.anchorJumpOriginBoardIDByDesk },
                writeAnchorOrigins: { navigation.anchorJumpOriginBoardIDByDesk = $0 },
                present: { navigation.present($0) },
                replacePresentedDesk: { navigation.replacePresentedDesk($0) },
                clearHistory: { navigation.clearHistory() }),
            feedback: output, pasteboard: windowPasteboard, inputSourceTracker: inputSourceTracker,
            canPresentDesk: canPresentDesk, onDeskPresentationRequest: onDeskPresentationRequest,
            onWillResetDen: onWillResetDen)
        let boardNavigation = BoardNavigation(context: context)
        let deskLinks = DeskLinkActions(context: context)
        let screenshots = BoardScreenshots(context: context)
        let facings = DeskFacings(context: context)
        let reset = DenResetActions(context: context)
        let boardRemoval = BoardRemovalPresentation(context: context, boardNavigation: boardNavigation)
        let boardOpening = BoardOpeningActions(context: context, boardNavigation: boardNavigation)
        let desks = DeskActions(context: context, boardNavigation: boardNavigation)
        let presets = DeskPresetActionsAdapter(context: context, facings: facings)
        let notifications = NotificationDelivery(context: context, boardNavigation: boardNavigation)
        let drawer = DrawerActions(context: context, boardOpening: boardOpening)
        let zmx = ZmxBoardActions(
            context: context, boardNavigation: boardNavigation, boardRemoval: boardRemoval, boardOpening: boardOpening)
        let input = InputOpeningActions(context: context, boardOpening: boardOpening, drawer: drawer)
        let sideBoards = SideBoardCreation(
            context: context, boardNavigation: boardNavigation, boardOpening: boardOpening, zmx: zmx)
        let essentials = EssentialActions(context: context, boardOpening: boardOpening, input: input)

        connection.runtimes = runtimes
        connection.windowResources = windowResources
        connection.boardNavigation = boardNavigation
        connection.boardOpening = boardOpening
        connection.boardRemoval = boardRemoval
        connection.drawer = drawer
        connection.feedback = output
        connection.presentedDeskID = { [weak navigation] in navigation?.presentedDeskID }
        connection.focusedBoardID = { [weak navigation] in navigation?.focusedDesk?.focusedBoardID }
        connection.invalidateBoards = { [weak navigation] in navigation?.invalidateBoards($0) }
        connection.invalidateDesk = { [weak navigation] in navigation?.invalidateDesk($0) }
        connection.onDownloadActivity = { [weak downloads] in downloads?.receive($0) }
        connection.onDisconnect = { [weak downloads] in
            guard let downloads else { return }
            for activity in downloads.activities { downloads.receive(.ended(id: activity.id)) }
        }
        resources.windowConnections.add(connection)
        self.resources = resources
        self.configuration = configuration
        self.pasteboard = windowPasteboard
        self.windowResources = windowResources
        self.connection = connection
        self.inputSourceTracker = inputSourceTracker
        self.navigation = navigation
        self.feedback = feedback
        self.downloads = downloads
        self.context = context
        self.runtimes = runtimes
        self.boardNavigation = boardNavigation
        self.boardRemoval = boardRemoval
        self.boardOpening = boardOpening
        self.desks = desks
        self.presets = presets
        self.deskLinks = deskLinks
        self.drawer = drawer
        self.input = input
        self.essentials = essentials
        self.notifications = notifications
        self.zmx = zmx
        self.sideBoards = sideBoards
        self.screenshots = screenshots
        self.facings = facings
        self.reset = reset
    }
}
