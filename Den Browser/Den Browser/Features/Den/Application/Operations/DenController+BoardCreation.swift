import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
    func boardCreationTarget(
        afterBoardID: BoardID? = nil, focus: Bool = true,
        origin: BoardOperationOrigin = .interactive, deskID: DeskID? = nil
    ) -> BoardCreation.Target {
        BoardCreation.Target(
            presentedDeskID: presentedDeskID, deskID: deskID, afterBoardID: afterBoardID,
            focus: focus, origin: origin)
    }

    func boardOpeningRequest(
        input: String, preferredWidth: Double?, afterBoardID: BoardID?, zmxRootSessionName: String? = nil
    ) -> BoardCreation.OpenRequest {
        BoardCreation.OpenRequest(
            input: input, width: preferredWidth ?? inheritedBoardWidth,
            target: boardCreationTarget(afterBoardID: afterBoardID),
            configuration: BoardOpening.Configuration(
                searchEngine: preferences.searchEngine,
                zmxConfigured: zmxClient.isConfigured,
                zellijConfigured: zellijClient.isConfigured,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
            zmxRootSessionName: zmxRootSessionName)
    }

    /// This callback is used only for the synchronous creation call; Profile operations do not retain it.
    func boardCreationNotifications(
        returnsToOpenBoard: Bool = false, existingRuntime: WebRuntime? = nil
    ) -> (BoardCreation.Notice) -> Void {
        { [self] notice in
            switch notice {
            case .willInsert(let board):
                if let existingRuntime {
                    if drawerPeekRuntime === existingRuntime { drawerPeekRuntime = nil }
                    attachWebRuntime(existingRuntime, to: board)
                }
            case .prepareLinkFocus(let boardID, let origin):
                _ = prepareBoardLinkFocus(boardID, origin: origin)
            case .suppressMutationAnimation:
                onWindowEffect?(.suppressBoardMutationAnimation)
            case .focusInsertedBoard(let deskID):
                onWindowEffect?(.clearBoardInputRequests)
                setFocusedDesk(deskID)
                onWindowEffect?(.dismissTemporaryPresentation)
                onWindowEffect?(.exitDenMode)
            case .didInsert(let board):
                if let existingRuntime {
                    updateBoard(
                        boardID: board.id, url: existingRuntime.webView.url, title: existingRuntime.webView.title)
                }
                if board.isWeb {
                    dispatchDenOperationEvent(.webBoardOpened)
                } else if board.isTerminal {
                    dispatchDenOperationEvent(.terminalBoardOpened)
                }
            case .focusTutorial(let boardID):
                focusBoard(boardID, exitsDenMode: true)
                onWindowEffect?(.dismissTemporaryPresentation)
            case .didOpenInput:
                onWindowEffect?(.openBoardResult(nil))
            case .selectZmxSession:
                onWindowEffect?(.presentZmxSessions(returnsToOpenBoard: returnsToOpenBoard, selectedSessionName: nil))
            }
        }
    }
}
