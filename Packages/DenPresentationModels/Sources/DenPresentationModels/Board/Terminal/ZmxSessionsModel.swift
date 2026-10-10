import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class ZmxSessionsModel {
    public nonisolated struct Operations: Sendable {
        public let load: @Sendable () async throws -> ZmxSessionSnapshot
        public let kill: @Sendable (String) async throws -> Void

        public init(
            load: @escaping @Sendable () async throws -> ZmxSessionSnapshot,
            kill: @escaping @Sendable (String) async throws -> Void
        ) {
            self.load = load
            self.kill = kill
        }
    }

    public private(set) var groups: [ZmxSessionGroup] = []
    public private(set) var processNames: [String: String] = [:]
    public private(set) var message: String?
    public private(set) var isLoading = false
    public private(set) var selectedSessionName: String?
    public private(set) var markedSessionNames: Set<String> = []
    public private(set) var filterPhase: FilterPhase = .inactive
    public private(set) var pendingDeletion: [String] = []
    public private(set) var query = ""

    @ObservationIgnored private let operations: () -> Operations
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var killTask: Task<Void, Never>?
    @ObservationIgnored private var selectionFallbackAfterDeletion: String?
    @ObservationIgnored private var refreshGeneration = 0

    public init(operations: @escaping () -> Operations) {
        self.operations = operations
    }

    deinit {
        refreshTask?.cancel()
        killTask?.cancel()
    }

    public var filteredGroups: [ZmxSessionGroup] {
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

    public var sessionNames: [String] {
        filteredGroups.flatMap { group in
            (group.isRootActive ? [group.rootSessionName] : []) + group.childSessionNames
        }
    }

    public var markedSessionCount: Int { markedSessionNames.count }

    public var hasMarkedSessions: Bool { !markedSessionNames.isEmpty }

    public var activeSessionCount: Int { activeSessionNames.count }

    public var isFilterInputActive: Bool { filterPhase == .filtering }

    public func isMarked(_ sessionName: String) -> Bool {
        markedSessionNames.contains(sessionName)
    }

    public func processName(for sessionName: String) -> String? {
        processNames[sessionName]
    }

    public func rootSessionName(for sessionName: String) -> String? {
        groups.first { $0.childSessionNames.contains(sessionName) }?.rootSessionName
    }

    public func start(selectedSessionName: String?) {
        refreshTask?.cancel()
        killTask?.cancel()
        refreshTask = nil
        killTask = nil
        self.selectedSessionName = selectedSessionName
        markedSessionNames = []
        selectionFallbackAfterDeletion = nil
        query = ""
        filterPhase = .inactive
        pendingDeletion = []
        refresh()
    }

    public func stop() {
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

    public func refresh() {
        refresh(using: operations())
    }

    private func refresh(using operations: Operations) {
        refreshTask?.cancel()
        refreshGeneration += 1
        let refreshGeneration = refreshGeneration
        isLoading = true
        message = nil
        refreshTask = Task { [weak self, operations] in
            do {
                let snapshot = try await operations.load()
                guard !Task.isCancelled, let self else { return }
                guard self.refreshGeneration == refreshGeneration else { return }
                self.isLoading = false
                self.groups = snapshot.groups
                self.processNames = snapshot.processNames
                self.updateSelection()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                guard self.refreshGeneration == refreshGeneration else { return }
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

    public func waitForRefresh() async {
        let refreshTask = refreshTask
        let killTask = killTask
        await refreshTask?.value
        await killTask?.value
        await self.refreshTask?.value
    }

    public func select(by offset: Int) {
        selectedSessionName = SelectionNavigation.next(
            selectedSessionName,
            among: sessionNames,
            by: offset
        )
    }

    public func select(sessionName: String) {
        guard sessionNames.contains(sessionName) else { return }
        selectedSessionName = sessionName
    }

    public func toggleMarking(_ sessionName: String) {
        guard sessionNames.contains(sessionName) else { return }
        if markedSessionNames.contains(sessionName) {
            markedSessionNames.remove(sessionName)
        } else {
            markedSessionNames.insert(sessionName)
        }
    }

    public func markAllVisible() {
        markedSessionNames = Set(sessionNames)
    }

    public func clearMarks() {
        markedSessionNames = []
    }

    public func enterFilter() {
        filterPhase = .filtering
        updateSelection()
    }

    public func setQuery(_ query: String) {
        self.query = query
        updateSelection()
    }

    public func exitFilter() {
        filterPhase = .inactive
        query = ""
        updateSelection()
    }

    public func clearFilter() {
        filterPhase = .inactive
        query = ""
        updateSelection()
    }

    public func requestDeletion(sessionName: String? = nil) {
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

    public func clearPendingDeletion() {
        pendingDeletion = []
    }

    public func kill(_ sessionName: String) {
        kill([sessionName])
    }

    public func kill(_ sessionNames: [String]) {
        let operations = self.operations()
        let sessionNames = sessionNames.uniqued()
        guard !sessionNames.isEmpty else { return }
        selectionFallbackAfterDeletion = selectionFallback(for: Set(sessionNames))
        pendingDeletion = []
        markedSessionNames.subtract(sessionNames)
        killTask?.cancel()
        killTask = Task { [weak self, operations] in
            var failures: [String] = []
            for sessionName in sessionNames {
                do {
                    try await operations.kill(sessionName)
                } catch is CancellationError {
                    return
                } catch {
                    failures.append("\(sessionName): \(error.localizedDescription)")
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.refresh(using: operations)
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
