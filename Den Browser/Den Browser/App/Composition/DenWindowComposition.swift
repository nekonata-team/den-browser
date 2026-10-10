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
                enterSelection: { controller.enterOverviewSelection(deskID: $0, boardID: $1) },
                beginDrag: { controller.beginOverviewBoardDrag($0) },
                finishDrag: { controller.finishOverviewBoardDrag($0, toDeskID: $1, at: $2) },
                cancelDrag: { controller.cancelOverviewBoardDrag() },
                moveBoard: { controller.moveOverviewBoardGroup($0, by: $1) },
                moveBoardToDesk: { controller.moveOverviewBoardGroupToDesk($0, by: $1) }))
        let drawer = DrawerModel(
            items: { controller.state.drawerItems },
            isBottomStyle: { controller.preferences.drawerStyle == .bottom },
            releasePreview: { controller.releaseDrawerPreview() },
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
        let openBoard = OpenBoardModel { input, width, afterBoardID in
            let rootSessionName: String?
            if case .session(let sessionName)? = DenController.resolveZmxInput(input) {
                rootSessionName = zmxSessions.rootSessionName(for: sessionName)
            } else {
                rootSessionName = nil
            }
            switch controller.requestOpenBoard(
                input: input,
                preferredWidth: width,
                afterBoardID: afterBoardID,
                opensFromOpenBoardPanel: true,
                zmxRootSessionName: rootSessionName)
            {
            case .accepted: return nil
            case .rejected(let message): return message
            }
        }
        let deskFilter = DeskFilterModel(
            focusedDesk: { controller.focusedDesk },
            focusBoard: { controller.focusBoard($0, exitsDenMode: true) })
        let notificationList = NotificationListModel(
            items: {
                controller.notifications.map { notification in
                    NotificationListItem(
                        notification: notification,
                        source: controller.notificationSource(for: notification).map {
                            NotificationListItem.Source(deskLabel: $0.deskLabel, boardLabel: $0.boardLabel)
                        })
                }
            },
            openNotification: { controller.openNotification($0) },
            requestClearConfirmation: { controller.requestNotificationClearConfirmation() })
        let model = DenWindowModel(
            overview: overview,
            drawer: drawer,
            openBoard: openBoard,
            deskFilter: deskFilter,
            notificationList: notificationList,
            zmxSessions: zmxSessions,
            onLaunchEssential: { controller.launchEssential(id: $0, preferredWidth: $1) },
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
            boardActions: DenWindowModel.BoardActions(
                adjustBoardWidth: { controller.adjustBoardWidth($0, by: $1) },
                adjustDeskBoardWidths: { controller.adjustDeskBoardWidths($0, by: $1) },
                resizeDeskBoards: { controller.resizeDeskBoards($0, to: $1) },
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
            feedbackDuration: feedbackDuration)
        self.model = model
        overview.onDismiss = { [weak model] in model?.hideOverview() }
        drawer.onPreviewExpanded = { [weak model] in model?.isDenMode = false }
        drawer.onClose = { [weak model] in model?.closeDrawer() }
        deskFilter.onCenterFocusedBoard = { [weak model] in model?.centerFocusedBoardRequest &+= 1 }
        notificationList.onClose = { [weak model] in model?.closeNotificationList() }
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
