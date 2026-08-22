import Foundation

nonisolated struct ZmxSessionGroup: Identifiable, Equatable, Sendable {
    let rootSessionName: String
    let isRootActive: Bool
    let childSessionNames: [String]

    var id: String { rootSessionName }
}

extension DenStore {
    var filteredZmxSessionGroups: [ZmxSessionGroup] {
        guard !zmxSessionQuery.isEmpty else { return zmxSessionGroups }
        return zmxSessionGroups.compactMap { group in
            let rootMatches = group.rootSessionName.localizedCaseInsensitiveContains(
                zmxSessionQuery)
            let childSessionNames: [String]
            if rootMatches {
                childSessionNames = group.childSessionNames
            } else {
                childSessionNames = group.childSessionNames.filter {
                    $0.localizedCaseInsensitiveContains(zmxSessionQuery)
                }
            }
            guard rootMatches || !childSessionNames.isEmpty else { return nil }
            return ZmxSessionGroup(
                rootSessionName: group.rootSessionName,
                isRootActive: group.isRootActive,
                childSessionNames: childSessionNames)
        }
    }

    var zmxSessionNames: [String] {
        filteredZmxSessionGroups.flatMap { group in
            (group.isRootActive ? [group.rootSessionName] : []) + group.childSessionNames
        }
    }

    func zmxSessionProcessName(for sessionName: String) -> String? {
        zmxSessionProcessNames[sessionName]
    }

    func refreshZmxSessions() {
        zmxSessionRefreshTask?.cancel()
        zmxSessionsIsLoading = true
        zmxSessionsMessage = nil
        let client = zmxClient
        zmxSessionRefreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                client.sessionSnapshot()
            }.value
            guard !Task.isCancelled else { return }
            guard let self else { return }
            zmxSessionsIsLoading = false
            guard let snapshot else {
                zmxSessionGroups = []
                zmxSessionProcessNames = [:]
                zmxSessionsMessage = "Could not list zmx Sessions."
                zmxSessionSelectedName = nil
                return
            }
            zmxSessionGroups = snapshot.groups
            zmxSessionProcessNames = snapshot.processNames
            if let selectedName = zmxSessionSelectedName, zmxSessionNames.contains(selectedName) {
                return
            }
            zmxSessionSelectedName = zmxSessionNames.first
        }
    }

    func selectZmxSession(by offset: Int) {
        let names = zmxSessionNames
        guard !names.isEmpty else { return }
        let currentIndex = zmxSessionSelectedName.flatMap { names.firstIndex(of: $0) } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), names.count - 1)
        zmxSessionSelectedName = names[nextIndex]
    }

    func enterZmxSessionFilter() {
        zmxSessionFilterPhase = .filtering
        updateZmxSessionSelection()
    }

    func setZmxSessionQuery(_ query: String) {
        zmxSessionQuery = query
        updateZmxSessionSelection()
    }

    func exitZmxSessionFilter() {
        zmxSessionFilterPhase = .inactive
        zmxSessionQuery = ""
        updateZmxSessionSelection()
    }

    func confirmZmxSessionFilterQuery() {
        guard zmxSessionFilterPhase == .filtering else { return }
        zmxSessionFilterPhase = .selecting
    }

    func clearZmxSessionFilter() {
        zmxSessionFilterPhase = .inactive
        zmxSessionQuery = ""
        updateZmxSessionSelection()
    }

    func openZmxSession(_ sessionName: String) {
        if let board = state.desks.lazy.flatMap(\.boards).first(where: { $0.zmxSessionName == sessionName }) {
            focusBoard(board.id, exitsDenMode: true)
            hideZmxSessions(returnToSource: false)
            return
        }
        guard addZmxBoard(sessionName: sessionName) else { return }
    }

    func openSelectedZmxSession() {
        guard let zmxSessionSelectedName else { return }
        openZmxSession(zmxSessionSelectedName)
    }

    func requestZmxSessionDeletion(_ sessionName: String? = nil) {
        zmxSessionPendingDeletion = sessionName ?? zmxSessionSelectedName
    }

    func killZmxSession(_ sessionName: String) {
        let client = zmxClient
        zmxSessionPendingDeletion = nil
        Task { [weak self] in
            let didKill = await Task.detached(priority: .userInitiated) {
                client.killSession(sessionName)
            }.value
            guard let self else { return }
            guard didKill else {
                zmxSessionsMessage = "Could not kill \(sessionName)."
                return
            }
            refreshZmxSessions()
        }
    }

    private func updateZmxSessionSelection() {
        let names = zmxSessionNames
        if let zmxSessionSelectedName, names.contains(zmxSessionSelectedName) { return }
        zmxSessionSelectedName = names.first
    }
}
