import Foundation
import Observation

nonisolated struct ZmxSessionGroup: Identifiable, Equatable, Sendable {
    let rootSessionName: String
    let isRootActive: Bool
    let childSessionNames: [String]

    var id: String { rootSessionName }
}

@MainActor
@Observable
final class ZmxSessionsModel {
    private(set) var groups: [ZmxSessionGroup] = []
    private(set) var processNames: [String: String] = [:]
    private(set) var message: String?
    private(set) var isLoading = false
    private(set) var selectedSessionName: String?
    private(set) var filterPhase: DenFilterPhase = .inactive
    private(set) var pendingDeletion: String?
    private(set) var query = ""

    @ObservationIgnored private var client: ZmxClient
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var killTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var lifecycleGeneration = 0

    init(client: ZmxClient = ZmxClient(executablePath: "")) {
        self.client = client
    }

    deinit {
        refreshTask?.cancel()
        killTask?.cancel()
    }

    var filteredGroups: [ZmxSessionGroup] {
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let rootMatches = group.rootSessionName.localizedCaseInsensitiveContains(query)
            let childSessionNames =
                rootMatches
                ? group.childSessionNames
                : group.childSessionNames.filter {
                    $0.localizedCaseInsensitiveContains(query)
                }
            guard rootMatches || !childSessionNames.isEmpty else { return nil }
            return ZmxSessionGroup(
                rootSessionName: group.rootSessionName,
                isRootActive: group.isRootActive,
                childSessionNames: childSessionNames)
        }
    }

    var sessionNames: [String] {
        filteredGroups.flatMap { group in
            (group.isRootActive ? [group.rootSessionName] : []) + group.childSessionNames
        }
    }

    var isFilterInputActive: Bool { filterPhase == .filtering }

    func processName(for sessionName: String) -> String? {
        processNames[sessionName]
    }

    func start(client: ZmxClient, selectedSessionName: String?) {
        refreshTask?.cancel()
        killTask?.cancel()
        refreshTask = nil
        killTask = nil
        lifecycleGeneration += 1
        self.client = client
        self.selectedSessionName = selectedSessionName
        query = ""
        filterPhase = .inactive
        pendingDeletion = nil
        refresh()
    }

    func stop() {
        lifecycleGeneration += 1
        refreshTask?.cancel()
        killTask?.cancel()
        refreshTask = nil
        killTask = nil
        groups = []
        processNames = [:]
        message = nil
        isLoading = false
        selectedSessionName = nil
        query = ""
        filterPhase = .inactive
        pendingDeletion = nil
    }

    func refresh(using client: ZmxClient? = nil) {
        if let client { self.client = client }
        refreshTask?.cancel()
        refreshGeneration += 1
        let refreshGeneration = refreshGeneration
        let lifecycleGeneration = lifecycleGeneration
        let client = self.client
        isLoading = true
        message = nil
        refreshTask = Task { [weak self, client] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                client.sessionSnapshot()
            }.value
            guard !Task.isCancelled, let self else { return }
            guard self.refreshGeneration == refreshGeneration,
                self.lifecycleGeneration == lifecycleGeneration
            else { return }
            self.isLoading = false
            guard let snapshot else {
                self.groups = []
                self.processNames = [:]
                self.message = "Could not list zmx Sessions."
                self.selectedSessionName = nil
                return
            }
            self.groups = snapshot.groups
            self.processNames = snapshot.processNames
            self.updateSelection()
        }
    }

    func waitForRefresh() async {
        await refreshTask?.value
        await killTask?.value
        await refreshTask?.value
    }

    func select(by offset: Int) {
        let names = sessionNames
        guard !names.isEmpty else { return }
        let currentIndex = selectedSessionName.flatMap { names.firstIndex(of: $0) } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), names.count - 1)
        selectedSessionName = names[nextIndex]
    }

    func select(sessionName: String) {
        guard sessionNames.contains(sessionName) else { return }
        selectedSessionName = sessionName
    }

    func enterFilter() {
        filterPhase = .filtering
        updateSelection()
    }

    func setQuery(_ query: String) {
        self.query = query
        updateSelection()
    }

    func exitFilter() {
        filterPhase = .inactive
        query = ""
        updateSelection()
    }

    func confirmFilterQuery() {
        guard filterPhase == .filtering else { return }
        filterPhase = .selecting
    }

    func clearFilter() {
        filterPhase = .inactive
        query = ""
        updateSelection()
    }

    func requestDeletion(sessionName: String? = nil) {
        pendingDeletion = sessionName ?? selectedSessionName
    }

    func clearPendingDeletion() {
        pendingDeletion = nil
    }

    func kill(_ sessionName: String, using client: ZmxClient? = nil) {
        if let client { self.client = client }
        let client = self.client
        let lifecycleGeneration = lifecycleGeneration
        pendingDeletion = nil
        killTask?.cancel()
        killTask = Task { [weak self, client] in
            let didKill = await Task.detached(priority: .userInitiated) {
                client.killSession(sessionName)
            }.value
            guard !Task.isCancelled, let self else { return }
            guard self.lifecycleGeneration == lifecycleGeneration else { return }
            guard didKill else {
                self.message = "Could not kill \(sessionName)."
                return
            }
            self.refresh(using: client)
        }
    }

    private func updateSelection() {
        let names = sessionNames
        if let selectedSessionName, names.contains(selectedSessionName) { return }
        selectedSessionName = names.first
    }
}
