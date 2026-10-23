import DenDomain
import DenInfrastructure
import Foundation
import Observation

@MainActor
@Observable
final class BoardActivitySampling {
    private let resources: DenProfileResources
    private var sampler = ProcessResourceSampler()
    private var webUsage: [pid_t: ProcessResourceUsage] = [:]
    private var terminalUsage: [BoardID: ProcessResourceUsage] = [:]

    init(resources: DenProfileResources) {
        self.resources = resources
    }

    func run() async {
        while !Task.isCancelled {
            refreshResourceUsage()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func usage(for board: BoardState) -> ProcessResourceUsage? {
        if let processID = resources.webRuntimes[board.id]?.webProcessIdentifier {
            return webUsage[processID]
        }
        return terminalUsage[board.id]
    }

    func sharedWebBoardCount(for board: BoardState) -> Int {
        guard let processID = resources.webRuntimes[board.id]?.webProcessIdentifier else { return 0 }
        return resources.webRuntimes.values.count { $0.webProcessIdentifier == processID }
    }

    func processLabel(for board: BoardState) -> String? {
        if let processID = resources.webRuntimes[board.id]?.webProcessIdentifier {
            return "Web PID \(processID)"
        }
        if let processGroupID = resources.terminalRuntimes[board.id]?.foregroundProcessGroupID {
            return "Terminal PGID \(processGroupID)"
        }
        return nil
    }

    func processIdentifier(for board: BoardState) -> pid_t? {
        resources.webRuntimes[board.id]?.webProcessIdentifier
            ?? resources.terminalRuntimes[board.id]?.foregroundProcessGroupID
    }

    private func refreshResourceUsage() {
        var activeSamplerKeys = Set<String>()
        let webProcessIDs = Set(resources.webRuntimes.values.compactMap(\.webProcessIdentifier))
        webUsage = Dictionary(
            uniqueKeysWithValues: webProcessIDs.compactMap { processID in
                let key = "web:\(processID)"
                activeSamplerKeys.insert(key)
                return sampler.usage(key: key, pids: [processID]).map { (processID, $0) }
            })

        terminalUsage = Dictionary(
            uniqueKeysWithValues: resources.terminalRuntimes.compactMap { boardID, runtime in
                guard let processGroupID = runtime.foregroundProcessGroupID else { return nil }
                let pids = ProcessResourceSampler.processGroupPIDs(processGroupID)
                let key = "terminal:\(boardID)"
                activeSamplerKeys.insert(key)
                return sampler.usage(key: key, pids: pids).map { (boardID, $0) }
            })
        sampler.removeSamples(keeping: activeSamplerKeys)
    }
}
