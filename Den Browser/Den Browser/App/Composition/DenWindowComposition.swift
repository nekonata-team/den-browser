import DenApplication
import DenDomain
import DenPresentation
import Foundation

@MainActor
final class DenWindowComposition {
    let store: DenStore
    let model: DenWindowModel

    init(store: DenStore, feedbackDuration: Duration = .seconds(5)) {
        self.store = store
        let overview = OverviewModel(
            desks: { store.state.desks },
            presentedDeskID: { store.presentedDeskID },
            focusedDesk: { store.focusedDesk },
            activeBoardID: {
                guard case .board(let id)? = store.activeDrag else { return nil }
                return id
            },
            isDragging: { store.activeDrag != nil },
            actions: OverviewModel.Actions(
                enterSelection: { store.enterOverviewSelection(deskID: $0, boardID: $1) },
                beginDrag: { store.beginOverviewBoardDrag($0) },
                finishDrag: { store.finishOverviewBoardDrag($0, toDeskID: $1, at: $2) },
                cancelDrag: { store.cancelOverviewBoardDrag() },
                moveBoard: { store.moveOverviewBoardGroup($0, by: $1) },
                moveBoardToDesk: { store.moveOverviewBoardGroupToDesk($0, by: $1) }))
        let drawer = DrawerModel(
            items: { store.state.drawerItems },
            isBottomStyle: { store.preferences.drawerStyle == .bottom },
            releasePreview: { store.releaseDrawerPreview() },
            discardItem: { itemID, focusNext in
                _ = store.discardDrawerItem(itemID, focusNext: focusNext)
            },
            toggleStyle: { store.preferences.toggleDrawerStyle() },
            requestClearConfirmation: { store.requestDrawerClearConfirmation() })
        let openBoard = OpenBoardModel { input, width, afterBoardID, rootSessionName in
            _ = store.openBoard(
                input: input,
                preferredWidth: width,
                afterBoardID: afterBoardID,
                opensFromOpenBoardPanel: true,
                zmxRootSessionName: rootSessionName)
        }
        let deskFilter = DeskFilterModel(
            focusedDesk: { store.focusedDesk },
            focusBoard: { store.focusBoard($0, exitsDenMode: true) })
        let notificationList = NotificationListModel(
            items: {
                store.notifications.map { notification in
                    NotificationListItem(
                        notification: notification,
                        source: store.notificationSource(for: notification).map {
                            NotificationListItem.Source(deskLabel: $0.deskLabel, boardLabel: $0.boardLabel)
                        })
                }
            },
            openNotification: { store.openNotification($0) },
            requestClearConfirmation: { store.requestNotificationClearConfirmation() })
        let model = DenWindowModel(
            store: store,
            overview: overview,
            drawer: drawer,
            openBoard: openBoard,
            deskFilter: deskFilter,
            notificationList: notificationList,
            feedbackDuration: feedbackDuration)
        self.model = model
        overview.onDismiss = { [weak model] in model?.hideOverview() }
        drawer.onPreviewExpanded = { [weak model] in model?.isDenMode = false }
        drawer.onClose = { [weak model] in model?.closeDrawer() }
        deskFilter.onCenterFocusedBoard = { [weak model] in model?.centerFocusedBoardRequest &+= 1 }
        notificationList.onClose = { [weak model] in model?.closeNotificationList() }
    }

    func connect() {
        store.onWindowEffect = { [weak model] effect in
            model?.receive(effect)
        }
        model.receive(.feedback(store.latestFeedback))
    }

    func disconnect() {
        store.onWindowEffect = nil
        model.endWindowPresentation()
    }
}
