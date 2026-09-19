import Foundation

extension DenStore {
    func refreshZmxSessions() {
        zmxSessions.refresh(using: zmxClient)
    }

    func selectZmxSession(by offset: Int) {
        zmxSessions.select(by: offset)
    }

    func toggleZmxSessionSelection() {
        guard let sessionName = zmxSessions.selectedSessionName else { return }
        zmxSessions.toggleMarking(sessionName)
    }

    func selectAllZmxSessions() {
        zmxSessions.markAllVisible()
    }

    func clearZmxSessionSelection() {
        zmxSessions.clearMarks()
    }

    func enterZmxSessionFilter() {
        zmxSessions.enterFilter()
    }

    func exitZmxSessionFilter() {
        zmxSessions.exitFilter()
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
        let trimmed = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        openBoard(input: ":zmx \(trimmed)")
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
        zmxSessions.kill(sessionNames, using: zmxClient)
    }

    func zmxBoardLocation(for sessionName: String) -> String? {
        for desk in state.desks {
            if let board = desk.boards.first(where: { $0.zmxSessionName == sessionName }) {
                return "\(desk.label) · \(board.displayName)"
            }
        }
        return nil
    }
}
