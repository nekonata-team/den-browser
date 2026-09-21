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
    private(set) var markedSessionNames: Set<String> = []
    private(set) var filterPhase: DenFilterPhase = .inactive
    private(set) var pendingDeletion: [String] = []
    private(set) var query = ""

    @ObservationIgnored private var client: ZmxClient
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var killTask: Task<Void, Never>?
    @ObservationIgnored private var selectionFallbackAfterDeletion: String?
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

    var markedSessionCount: Int { markedSessionNames.count }

    var hasMarkedSessions: Bool { !markedSessionNames.isEmpty }

    var activeSessionCount: Int { activeSessionNames.count }

    var isFilterInputActive: Bool { filterPhase == .filtering }

    func isMarked(_ sessionName: String) -> Bool {
        markedSessionNames.contains(sessionName)
    }

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
        markedSessionNames = []
        selectionFallbackAfterDeletion = nil
        query = ""
        filterPhase = .inactive
        pendingDeletion = []
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
        markedSessionNames = []
        selectionFallbackAfterDeletion = nil
        query = ""
        filterPhase = .inactive
        pendingDeletion = []
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
            do {
                let snapshot = try await client.sessionSnapshot()
                guard !Task.isCancelled, let self else { return }
                guard self.refreshGeneration == refreshGeneration,
                    self.lifecycleGeneration == lifecycleGeneration
                else { return }
                self.isLoading = false
                self.groups = snapshot.groups
                self.processNames = snapshot.processNames
                self.updateSelection()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                guard self.refreshGeneration == refreshGeneration,
                    self.lifecycleGeneration == lifecycleGeneration
                else { return }
                self.isLoading = false
                self.groups = []
                self.processNames = [:]
                self.message = "Could not list zmx Sessions: \(error.localizedDescription)"
                self.selectedSessionName = nil
                self.markedSessionNames = []
                self.selectionFallbackAfterDeletion = nil
            }
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

    func toggleMarking(_ sessionName: String) {
        guard sessionNames.contains(sessionName) else { return }
        if markedSessionNames.contains(sessionName) {
            markedSessionNames.remove(sessionName)
        } else {
            markedSessionNames.insert(sessionName)
        }
    }

    func markAllVisible() {
        markedSessionNames = Set(sessionNames)
    }

    func clearMarks() {
        markedSessionNames = []
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

    func clearFilter() {
        filterPhase = .inactive
        query = ""
        updateSelection()
    }

    func requestDeletion(sessionName: String? = nil) {
        let targets =
            if let sessionName {
                [sessionName]
            } else if !markedSessionNames.isEmpty {
                activeSessionNames.filter(markedSessionNames.contains)
            } else {
                selectedSessionName.map { [$0] } ?? []
            }
        pendingDeletion = targets
    }

    func clearPendingDeletion() {
        pendingDeletion = []
    }

    func kill(_ sessionName: String, using client: ZmxClient? = nil) {
        kill([sessionName], using: client)
    }

    func kill(_ sessionNames: [String], using client: ZmxClient? = nil) {
        if let client { self.client = client }
        let client = self.client
        let lifecycleGeneration = lifecycleGeneration
        let sessionNames = sessionNames.uniqued()
        guard !sessionNames.isEmpty else { return }
        selectionFallbackAfterDeletion = selectionFallback(for: Set(sessionNames))
        pendingDeletion = []
        markedSessionNames.subtract(sessionNames)
        killTask?.cancel()
        killTask = Task { [weak self, client] in
            var failures: [String] = []
            for sessionName in sessionNames {
                do {
                    try await client.killSession(sessionName)
                } catch is CancellationError {
                    return
                } catch {
                    failures.append("\(sessionName): \(error.localizedDescription)")
                }
            }
            guard !Task.isCancelled, let self else { return }
            guard self.lifecycleGeneration == lifecycleGeneration else { return }
            self.refresh(using: client)
            if !failures.isEmpty {
                self.message = "Could not end \(failures.joined(separator: ", "))."
            }
        }
    }

    private func updateSelection() {
        let names = sessionNames
        let activeNames = Set(activeSessionNames)
        markedSessionNames = markedSessionNames.filter(activeNames.contains)
        if let selectedSessionName, names.contains(selectedSessionName) {
            selectionFallbackAfterDeletion = nil
            return
        }
        selectedSessionName =
            selectionFallbackAfterDeletion.flatMap { fallback in
                names.contains(fallback) ? fallback : nil
            } ?? names.first
        selectionFallbackAfterDeletion = nil
    }

    private func selectionFallback(for deletedSessionNames: Set<String>) -> String? {
        guard
            let selectedSessionName,
            deletedSessionNames.contains(selectedSessionName),
            let selectedIndex = sessionNames.firstIndex(of: selectedSessionName)
        else { return nil }

        if let next = sessionNames.dropFirst(selectedIndex + 1).first(where: {
            !deletedSessionNames.contains($0)
        }) {
            return next
        }
        return sessionNames[..<selectedIndex].reversed().first(where: {
            !deletedSessionNames.contains($0)
        })
    }

    private var activeSessionNames: [String] {
        groups.flatMap { group in
            (group.isRootActive ? [group.rootSessionName] : []) + group.childSessionNames
        }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
