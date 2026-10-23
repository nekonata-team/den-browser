import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
final class DenWindowComposition {
    let session: ProfileWindowSession
    let model: DenWindowModel

    init(session: ProfileWindowSession, feedbackDuration: Duration = .seconds(5)) {
        self.session = session
        let state = session.resources.data
        let navigation = session.navigation
        let preferences = session.configuration.preferences
        let boardEditing = BoardEditingModel(
            state: session.resources.data, updates: session.resources.boardUpdates,
            recents: session.resources.recents, movement: session.resources.boardMovement,
            focusedBoard: { navigation.focusedBoard }, essentials: { preferences.essentials },
            searchEngine: { session.configuration.preferences.searchEngine },
            finishEditing: {
                session.connection.onWindowEffect?(.dismissTemporaryPresentation)
                session.connection.onWindowEffect?(.exitDenMode)
            },
            loadURL: { session.resources.webRuntimes[$0]?.load($1) },
            restoreInput: { session.runtimes.restoreFocusedFirstResponder() },
            duplicateZmx: { session.zmx.duplicateFocusedZmxBoard(suffix: $0) },
            focus: { session.boardNavigation.focusBoard($0) }, center: { session.boardNavigation.centerFocusedBoard() })
        let overview = OverviewModel(
            desks: { state.snapshot.den.desks },
            presentedDeskID: { [navigation = session.navigation] in navigation.presentedDeskID },
            focusedDesk: { navigation.focusedDesk },
            activeBoardID: {
                guard case .board(let id)? = state.snapshot.activeDrag else { return nil }
                return id
            },
            isDragging: { state.snapshot.activeDrag != nil },
            actions: OverviewModel.Actions(
                removeBoard: {
                    session.resources.boardRemoval.remove(
                        $0, presentedDeskID: navigation.presentedDeskID, focusNext: $1,
                        notify: session.boardRemoval.boardRemovalNotifications())
                },
                restoreBoard: {
                    let result = session.resources.boardRemoval.restore(
                        presentedDeskID: navigation.presentedDeskID, present: false,
                        notify: session.boardRemoval.boardRemovalNotifications())
                    return session.boardRemoval.handleBoardRestorationResult(result, present: false)
                },
                enterSelection: { session.boardNavigation.enterOverviewSelection(deskID: $0, boardID: $1) },
                beginDrag: { session.resources.boardMovement.beginOverviewDrag($0) },
                finishDrag: { session.resources.boardMovement.finishOverviewDrag($0, to: $1, at: $2) },
                cancelDrag: { session.resources.boardMovement.cancelOverviewDrag() },
                moveBoard: { session.resources.boardMovement.shiftInOverview($0, by: $1) },
                moveBoardToDesk: { session.resources.boardMovement.transferInOverview($0, by: $1) }))
        let drawer = DrawerModel(
            items: { state.snapshot.den.drawerItems },
            isBottomStyle: { session.configuration.preferences.drawerStyle == .bottom },
            releasePeek: { session.runtimes.releaseDrawerPeek() },
            discardItem: { itemID, focusNext in
                session.resources.drawerItems.discard(
                    itemID, focusNext: focusNext, notify: session.drawer.drawerItemNotifications())
            },
            toggleStyle: { session.configuration.preferences.toggleDrawerStyle() },
            requestClearConfirmation: { session.drawer.requestDrawerClearConfirmation() })
        let zmxSessions = ZmxSessionsModel {
            let client = session.context.zmxClient
            return ZmxSessionsModel.Operations(
                load: { try await client.sessionSnapshot() },
                kill: { try await client.killSession($0) })
        }
        let openBoard = OpenBoardModel(
            creation: session.resources.boardCreation,
            openingRequest: { input, width, afterBoardID in
                let rootSessionName: String?
                if case .session(let sessionName)? = BoardInputResolver.resolveZmxInput(input) {
                    rootSessionName = zmxSessions.rootSessionName(for: sessionName)
                } else {
                    rootSessionName = nil
                }
                return session.boardOpening.boardOpeningRequest(
                    input: input, preferredWidth: width, afterBoardID: afterBoardID,
                    zmxRootSessionName: rootSessionName)
            },
            notify: session.boardOpening.boardCreationNotifications(returnsToOpenBoard: true),
            openInDrawer: { session.input.openInDrawer(input: $0) })
        let deskFilter = DeskFilterModel(
            focusedDesk: { navigation.focusedDesk },
            focusBoard: { session.boardNavigation.focusBoard($0, exitsDenMode: true) })
        let notificationList = NotificationListModel(
            state: session.resources.data,
            operations: session.resources.notificationOperations,
            openSource: session.notifications.openNotificationSource)
        let desks = DeskListModel(
            state: session.resources.data, lifecycle: session.resources.deskLifecycle,
            movement: session.resources.deskMovement, updates: session.resources.deskUpdates,
            navigation: session.navigation,
            isAvailable: { session.context.canPresentDesk?($0) ?? true },
            select: { session.boardNavigation.focusDesk($0) },
            notify: session.desks.deskLifecycleNotifications(),
            didDuplicate: { source, copy in
                for (original, duplicate) in zip(source.boards.filter { !$0.isTutorial }, copy.boards) {
                    if let image = session.resources.facingCache.image(for: original.id) {
                        session.resources.facingCache.setFacing(image, for: duplicate.id, at: nil)
                    }
                }
            },
            requestDeletion: { session.connection.onWindowEffect?(.requestConfirmation(.deleteDesk($0))) },
            warn: { session.context.feedback.publish($0, severity: .warning) },
            finishEditing: {
                session.connection.onWindowEffect?(.dismissTemporaryPresentation)
                session.connection.onWindowEffect?(.exitDenMode)
            },
            copyID: { session.desks.copyDeskID($0) }, exportLinks: { session.deskLinks.exportDeskLinks(for: $0) },
            copyLinks: { session.deskLinks.copyDeskLinks(for: $0) },
            create: { label, selection in
                switch selection {
                case .builtIn(let preset): session.desks.createDesk(label: label, preset: preset)
                case .personal(let id): session.desks.createDesk(label: label, personalPresetID: id)
                case .newDesk: session.desks.createDesk(label: label, preset: .empty)
                }
            },
            replace: { label, selection in
                switch selection {
                case .builtIn(let preset): session.desks.replaceFocusedDesk(label: label, preset: preset)
                case .personal(let id): session.desks.replaceFocusedDesk(label: label, personalPresetID: id)
                case .newDesk: .unavailable
                }
            })
        let model = DenWindowModel(
            boardEditing: boardEditing,
            desks: desks, downloads: session.downloads,
            overview: overview,
            drawer: drawer,
            openBoard: openBoard,
            deskFilter: deskFilter,
            notificationList: notificationList,
            zmxSessions: zmxSessions,
            onLaunchEssential: { session.essentials.launchEssential(id: $0, preferredWidth: $1, inDrawer: $2) },
            onSaveEssential: { session.essentials.saveEssential(name: $0, key: $1, input: $2) },
            onConfirmOperation: { request in
                switch request {
                case .resetDen: session.reset.resetDen()
                case .deleteDesk(let desk): session.desks.confirmDeskDeletion(desk.id)
                case .replaceDesk(let replacement): session.desks.confirmDeskReplacement(replacement)
                case .deleteDeskPreset(let preset): session.presets.deleteDeskPreset(preset.id)
                case .replaceDeskPreset(let replacement): return session.presets.replaceDeskPreset(replacement)
                case .replaceEssential(_, let replacement): return session.essentials.replaceEssential(replacement)
                case .endZmxSession(let name): session.zmx.endZmxSession(name)
                case .clearDrawer: session.drawer.clearDrawer()
                case .clearNotifications: session.notifications.clearNotifications()
                }
                return true
            },
            inputs: DenWindowModel.Inputs(
                essentials: { preferences.essentials },
                isBoardRailPresented: { session.configuration.preferences.isBoardRailPresented },
                isBoardDragging: {
                    guard case .board? = state.snapshot.activeDrag else { return false }
                    return true
                },
                isDeskDragging: {
                    guard case .desk? = state.snapshot.activeDrag else { return false }
                    return true
                }),
            windowActions: DenWindowModel.WindowActions(
                setBoardRailPresented: { session.configuration.preferences.setBoardRailPresented($0) },
                openFeedbackTarget: { session.notifications.openFeedbackTarget($0) },
                reportWarning: { session.context.feedback.publish($0, severity: .warning) },
                didEnterDenMode: { session.resources.recordOperation(.denModeEntered) },
                didShowKeyboardShortcuts: { session.resources.recordOperation(.keyboardShortcutsShown) }),
            boardSizing: session.resources.boardSizing,
            boardActions: DenWindowModel.BoardActions(
                placeDrawerItem: { session.drawer.placeDrawerItemAsBoard($0, preferredWidth: $1) },
                focusBoard: { session.boardNavigation.focusBoard($0, exitsDenMode: $1) },
                centerFocusedBoard: { session.boardNavigation.centerFocusedBoard() },
                cancelBoardDrag: { session.boardNavigation.requestBoardDragCancellation() },
                cancelDeskDrag: { session.boardNavigation.requestDeskDragCancellation() }),
            zmxActions: DenWindowModel.ZmxActions(
                canPresentSessions: { session.zmx.canPresentZmxSessions() },
                openSession: {
                    session.zmx.openZmxSession(
                        $0, preferredWidth: $1,
                        rootSessionName: { zmxSessions.rootSessionName(for: $0) },
                        opensFromOpenBoardPanel: $2)
                },
                boardLocation: { sessionName in
                    for desk in state.snapshot.den.desks {
                        if let board = desk.boards.first(where: { $0.zmxSessionName == sessionName }) {
                            return "\(desk.label) · \(board.displayName)"
                        }
                    }
                    return nil
                },
                cancelDuplication: { session.zmx.cancelZmxDuplicationRequest() }),
            deskPresetActions: DeskPresetActions(
                save: { session.presets.saveFocusedDeskAsPreset(label: $0) },
                rename: { session.presets.renameDeskPreset($0, to: $1) },
                requestDeletion: { session.presets.requestDeskPresetDeletion($0) }),
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
        session.connection.onWindowEffect = { [weak model] effect in
            model?.receive(effect)
        }
        model.receive(.feedback(session.feedback.latest))
    }

    func disconnect() {
        session.connection.onWindowEffect = nil
        model.endWindowPresentation()
    }
}
