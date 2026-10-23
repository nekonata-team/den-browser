public import DenDomain
public import Foundation
import Observation

@MainActor
@Observable
public final class InspectionBoardModel {
    public let runtimeID: UUID?
    @ObservationIgnored public let targetBoard: () -> BoardState?
    @ObservationIgnored public let pageGeneration: () -> Int
    @ObservationIgnored public let hasPage: () -> Bool
    @ObservationIgnored public let isActive: () -> Bool
    @ObservationIgnored public let startCollection: (ProfileRGB?) -> Void
    @ObservationIgnored public let setHighlightColor: (ProfileRGB?) -> Void
    @ObservationIgnored public let beginPicking: (ProfileRGB?) -> Void
    @ObservationIgnored public let selectNode: (String) -> Void
    @ObservationIgnored public let highlightNode: (String?) -> Void
    @ObservationIgnored public let readSnapshot: () async -> InspectionPageSnapshot
    @ObservationIgnored public let readChildren: (String) async -> [InspectionDOMNode]
    @ObservationIgnored public let refreshChildren: ([String]) async -> [String: [InspectionDOMNode]]

    public private(set) var snapshot = InspectionPageSnapshot.empty
    public private(set) var expandedNodeIDs: Set<String> = []
    public private(set) var loadedChildren: [String: [InspectionDOMNode]] = [:]
    public private(set) var loadingNodeIDs: Set<String> = []
    @ObservationIgnored private var childTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var observedPageGeneration = 0

    public init(
        runtimeID: UUID?, targetBoard: @escaping () -> BoardState?, pageGeneration: @escaping () -> Int,
        hasPage: @escaping () -> Bool, isActive: @escaping () -> Bool, startCollection: @escaping (ProfileRGB?) -> Void,
        setHighlightColor: @escaping (ProfileRGB?) -> Void, beginPicking: @escaping (ProfileRGB?) -> Void,
        selectNode: @escaping (String) -> Void, highlightNode: @escaping (String?) -> Void,
        readSnapshot: @escaping () async -> InspectionPageSnapshot,
        readChildren: @escaping (String) async -> [InspectionDOMNode],
        refreshChildren: @escaping ([String]) async -> [String: [InspectionDOMNode]]
    ) {
        self.runtimeID = runtimeID
        self.targetBoard = targetBoard
        self.pageGeneration = pageGeneration
        self.hasPage = hasPage
        self.isActive = isActive
        self.startCollection = startCollection
        self.setHighlightColor = setHighlightColor
        self.beginPicking = beginPicking
        self.selectNode = selectNode
        self.highlightNode = highlightNode
        self.readSnapshot = readSnapshot
        self.readChildren = readChildren
        self.refreshChildren = refreshChildren
    }

    public func generationChanged(_ generation: Int) {
        guard generation != observedPageGeneration else { return }
        observedPageGeneration = generation
        cancelLoading()
        snapshot = .empty
        expandedNodeIDs.removeAll()
        loadedChildren.removeAll()
    }

    public func observe() async {
        defer { cancelLoading() }
        while !Task.isCancelled {
            guard runtimeID != nil else { return }
            let generation = pageGeneration()
            let nextSnapshot = await readSnapshot()
            let children = await refreshChildren(Array(loadedChildren.keys))
            guard !Task.isCancelled else { return }
            if generation == pageGeneration() {
                let pathChanged = snapshot.treePath.map(\.id) != nextSnapshot.treePath.map(\.id)
                snapshot = nextSnapshot
                for (nodeID, refreshed) in children where loadedChildren[nodeID] != nil {
                    loadedChildren[nodeID] = refreshed
                }
                if pathChanged, snapshot.treePath.isEmpty {
                    cancelLoading()
                    expandedNodeIDs.removeAll()
                    loadedChildren.removeAll()
                } else if pathChanged {
                    expandedNodeIDs.formUnion(snapshot.treePath.dropLast().map(\.id))
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    public func children(for node: InspectionDOMNode) -> [InspectionDOMNode] {
        if let loaded = loadedChildren[node.id] { return loaded }
        guard let index = snapshot.treePath.firstIndex(where: { $0.id == node.id }),
            snapshot.treePath.indices.contains(index + 1)
        else { return [] }
        return [snapshot.treePath[index + 1]]
    }

    public func toggleDOMNode(_ node: InspectionDOMNode) {
        if expandedNodeIDs.contains(node.id),
            loadedChildren[node.id] != nil || children(for: node).count >= node.childCount
        {
            expandedNodeIDs.remove(node.id)
            return
        }
        expandedNodeIDs.insert(node.id)
        guard loadedChildren[node.id] == nil, !loadingNodeIDs.contains(node.id) else { return }
        loadingNodeIDs.insert(node.id)
        let requestedRevision = revision
        let generation = pageGeneration()
        childTasks[node.id] = Task { [weak self] in
            guard let self else { return }
            let children = await readChildren(node.id)
            guard !Task.isCancelled, requestedRevision == revision else { return }
            defer {
                childTasks.removeValue(forKey: node.id)
                loadingNodeIDs.remove(node.id)
            }
            guard isActive(), generation == pageGeneration() else { return }
            loadedChildren[node.id] = children
        }
    }

    public func cancelLoading() {
        revision += 1
        for task in childTasks.values { task.cancel() }
        childTasks.removeAll()
        loadingNodeIDs.removeAll()
    }
}
