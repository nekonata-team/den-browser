import DenApplication
import DenDomain
import DenPresentation
import Foundation

extension DenWindowModel {
    func refreshZmxSessions() {
        zmxSessions.refresh()
    }

    func selectZmxSession(by offset: Int) {
        zmxSessions.select(by: offset)
    }

    func toggleZmxSessionSelection() {
        guard let sessionName = zmxSessions.selectedSessionName else { return }
        zmxSessions.toggleMarking(sessionName)
    }

    func selectAllZmxSessions() { zmxSessions.markAllVisible() }
    func clearZmxSessionSelection() { zmxSessions.clearMarks() }
    func enterZmxSessionFilter() { zmxSessions.enterFilter() }
    func exitZmxSessionFilter() { zmxSessions.exitFilter() }
    func clearZmxSessionFilter() { zmxSessions.clearFilter() }

    func openZmxSession(_ sessionName: String) {
        if case .focusedExistingBoard = zmxActions.openSession(
            sessionName, defaultBoardWidth, zmxSessionsReturnToOpenBoard)
        {
            hideZmxSessions(returnToSource: false)
        }
    }

    func openSelectedZmxSession() {
        guard let selectedSessionName = zmxSessions.selectedSessionName else { return }
        openZmxSession(selectedSessionName)
    }

    func requestZmxSessionDeletion(_ sessionName: String? = nil) {
        zmxSessions.requestDeletion(sessionName: sessionName)
    }

    func killZmxSession(_ sessionName: String) {
        killZmxSessions([sessionName])
    }

    func killZmxSessions(_ sessionNames: [String]) {
        zmxSessions.kill(sessionNames)
    }

    func zmxBoardLocation(for sessionName: String) -> String? {
        zmxActions.boardLocation(sessionName)
    }
}
