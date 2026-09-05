import Foundation

extension DenStore {
    func refreshZmxSessions() {
        zmxSessions.refresh(using: zmxClient)
    }

    func selectZmxSession(by offset: Int) {
        zmxSessions.select(by: offset)
    }

    func enterZmxSessionFilter() {
        zmxSessions.enterFilter()
    }

    func exitZmxSessionFilter() {
        zmxSessions.exitFilter()
    }

    func confirmZmxSessionFilterQuery() {
        zmxSessions.confirmFilterQuery()
    }

    func clearZmxSessionFilter() {
        zmxSessions.clearFilter()
    }

    func openZmxSession(_ sessionName: String) {
        if let board = state.desks.lazy.flatMap(\.boards).first(where: { $0.zmxSessionName == sessionName }) {
            focusBoard(board.id, exitsDenMode: true)
            hideZmxSessions(returnToSource: false)
            return
        }
        guard
            addZmxBoard(
                sessionName: sessionName,
                recentItem: .zmx(
                    sessionName: sessionName.trimmingCharacters(in: .whitespacesAndNewlines)))
        else { return }
    }

    func openSelectedZmxSession() {
        guard let selectedSessionName = zmxSessions.selectedSessionName else { return }
        openZmxSession(selectedSessionName)
    }

    func requestZmxSessionDeletion(_ sessionName: String? = nil) {
        zmxSessions.requestDeletion(sessionName: sessionName)
    }

    func killZmxSession(_ sessionName: String) {
        zmxSessions.kill(sessionName, using: zmxClient)
    }
}
