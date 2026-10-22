import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
final class DenWindowComposition {
    let controller: DenController
    let model: DenWindowModel

    init(controller: DenController, feedbackDuration: Duration = .seconds(5)) {
        self.controller = controller
        let overview = OverviewModel(
            desks: { controller.state.desks },
            presentedDeskID: { controller.presentedDeskID },
            focusedDesk: { controller.focusedDesk },
            activeBoardID: {
                guard case .board(let id)? = controller.activeDrag else { return nil }
                return id
            },
            isDragging: { controller.activeDrag != nil },
            actions: OverviewModel.Actions(
                removeBoard: {
                    controller.storage.boardRemoval.remove(
                        $0, presentedDeskID: controller.presentedDeskID, focusNext: $1,
                        notify: controller.boardRemovalNotifications())
                },
                restoreBoard: {
                    let result = controller.storage.boardRemoval.restore(
                        presentedDeskID: controller.presentedDeskID, present: false,
                        notify: controller.boardRemovalNotifications())
                    return controller.handleBoardRestorationResult(result, present: false)
                },
                enterSelection: { controller.enterOverviewSelection(deskID: $0, boardID: $1) },
                beginDrag: { controller.storage.boardMovement.beginOverviewDrag($0) },
                finishDrag: { controller.storage.boardMovement.finishOverviewDrag($0, to: $1, at: $2) },
                cancelDrag: { controller.storage.boardMovement.cancelOverviewDrag() },
                moveBoard: { controller.storage.boardMovement.shiftInOverview($0, by: $1) },
                moveBoardToDesk: { controller.storage.boardMovement.transferInOverview($0, by: $1) }))
        let drawer = DrawerModel(
            items: { controller.state.drawerItems },
            isBottomStyle: { controller.preferences.drawerStyle == .bottom },
            releasePeek: { controller.releaseDrawerPeek() },
            discardItem: { itemID, focusNext in
                _ = controller.discardDrawerItem(itemID, focusNext: focusNext)
            },
            toggleStyle: { controller.preferences.toggleDrawerStyle() },
            requestClearConfirmation: { controller.requestDrawerClearConfirmation() })
        let zmxSessions = ZmxSessionsModel {
            let client = controller.zmxClient
            return ZmxSessionsModel.Operations(
                load: { try await client.sessionSnapshot() },
                kill: { try await client.killSession($0) })
        }
        let openBoard = OpenBoardModel(
            creation: controller.storage.boardCreation,
            openingRequest: { input, width, afterBoardID in
                let rootSessionName: String?
                if case .session(let sessionName)? = BoardInputResolver.resolveZmxInput(input) {
                    rootSessionName = zmxSessions.rootSessionName(for: sessionName)
                } else {
                    rootSessionName = nil
                }
                return controller.boardOpeningRequest(
                    input: input, preferredWidth: width, afterBoardID: afterBoardID,
                    zmxRootSessionName: rootSessionName)
            },
            notify: controller.boardCreationNotifications(returnsToOpenBoard: true),
            openInDrawer: { controller.openInDrawer(input: $0) })
        let deskFilter = DeskFilterModel(
            focusedDesk: { controller.focusedDesk },
            focusBoard: { controller.focusBoard($0, exitsDenMode: true) })
        let notificationList = NotificationListModel(
            state: controller.storage.data,
            operations: controller.storage.notificationOperations,
            openSource: controller.openNotificationSource)
        let model = DenWindowModel(
            overview: overview,
            drawer: drawer,
            openBoard: openBoard,
            deskFilter: deskFilter,
            notificationList: notificationList,
            zmxSessions: zmxSessions,
            onLaunchEssential: { controller.launchEssential(id: $0, preferredWidth: $1, inDrawer: $2) },
            onSaveEssential: { controller.saveEssential(name: $0, key: $1, input: $2) },
            onConfirmOperation: { controller.performConfirmedOperation($0) },
            inputs: DenWindowModel.Inputs(
                focusedDesk: { controller.focusedDesk },
                focusedBoard: { controller.focusedBoard },
                board: { controller.board(for: $0) },
                essentials: { controller.essentials },
                isBoardRailPresented: { controller.preferences.isBoardRailPresented },
                isBoardDragging: {
                    guard case .board? = controller.activeDrag else { return false }
                    return true
                },
                isDeskDragging: {
                    guard case .desk? = controller.activeDrag else { return false }
                    return true
                },
                canCreateDesk: { controller.canCreateDesk }),
            windowActions: DenWindowModel.WindowActions(
                setBoardRailPresented: { controller.preferences.setBoardRailPresented($0) },
                openFeedbackTarget: { controller.openFeedbackTarget($0) },
                reportWarning: { controller.reportFeedback($0, severity: .warning) },
                didEnterDenMode: { controller.dispatchDenOperationEvent(.denModeEntered) },
                didShowKeyboardShortcuts: { controller.dispatchDenOperationEvent(.keyboardShortcutsShown) }),
            boardSizing: controller.storage.boardSizing,
            boardActions: DenWindowModel.BoardActions(
                placeDrawerItem: { controller.placeDrawerItemAsBoard($0, preferredWidth: $1) },
                focusBoard: { controller.focusBoard($0, exitsDenMode: $1) },
                centerFocusedBoard: { controller.centerFocusedBoard() },
                cancelBoardDrag: { controller.requestBoardDragCancellation() },
                cancelDeskDrag: { controller.requestDeskDragCancellation() }),
            zmxActions: DenWindowModel.ZmxActions(
                canPresentSessions: { controller.canPresentZmxSessions() },
                openSession: {
                    controller.openZmxSession(
                        $0, preferredWidth: $1,
                        rootSessionName: { zmxSessions.rootSessionName(for: $0) },
                        opensFromOpenBoardPanel: $2)
                },
                boardLocation: { sessionName in
                    for desk in controller.state.desks {
                        if let board = desk.boards.first(where: { $0.zmxSessionName == sessionName }) {
                            return "\(desk.label) · \(board.displayName)"
                        }
                    }
                    return nil
                },
                cancelDuplication: { controller.cancelZmxDuplicationRequest() }),
            deskPresetActions: DeskPresetActions(
                save: { controller.saveFocusedDeskAsPreset(label: $0) },
                rename: { controller.renameDeskPreset($0, to: $1) },
                requestDeletion: { controller.requestDeskPresetDeletion($0) }),
            feedbackDuration: feedbackDuration)
        self.model = model
        overview.onDismiss = { [weak model] in model?.hideOverview() }
        drawer.onPeekExpanded = { [weak model] in model?.isDenMode = false }
        drawer.onClose = { [weak model] in model?.closeDrawer() }
        deskFilter.onCenterFocusedBoard = { [weak model] in model?.centerFocusedBoardRequest &+= 1 }
        notificationList.onClose = { [weak model] in model?.closeNotificationList() }
        notificationList.onRequestClearConfirmation = { [weak model] count in
            model?.requestNotificationClearConfirmation(count: count)
        }
    }

    func connect() {
        controller.onWindowEffect = { [weak model] effect in
            model?.receive(effect)
        }
        model.receive(.feedback(controller.latestFeedback))
    }

    func disconnect() {
        controller.onWindowEffect = nil
        model.endWindowPresentation()
    }
}
