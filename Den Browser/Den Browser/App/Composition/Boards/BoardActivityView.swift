import DenDomain
import DenPresentationModels
import DenViews
import GhosttyTerminal
import SFSafeSymbols
import SwiftUI

struct BoardActivityView: View {
    let profileColor: Color
    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel
    @State private var sampler = ProcessResourceSampler()
    @State private var webUsage: [pid_t: ProcessResourceUsage] = [:]
    @State private var terminalUsage: [BoardID: ProcessResourceUsage] = [:]

    var body: some View {
        DenViews.BoardActivityView(profileColor: profileColor) { board in
            DenViews.BoardActivityRow(
                board: board, usage: usage(for: board),
                processLabel: processLabel(for: board), processIdentifier: processIdentifier(for: board),
                sharedWebBoardCount: sharedWebBoardCount(for: board), profileColor: profileColor,
                onOpen: { windowModel.enterBoardFromActivity(board.id) },
                onRemove: { controller.removeBoard(board.id) },
                stateIcon: {
                    if let runtime = controller.webRuntimes[board.id] {
                        ObservedWebActivityIcon(runtime: runtime)
                    } else if controller.terminalRuntimes[board.id] != nil {
                        DenViews.TerminalActivityStateIcon()
                    } else {
                        Image(systemSymbol: .circle).foregroundStyle(.secondary).accessibilityLabel("Not active")
                    }
                },
                status: {
                    if let runtime = controller.terminalRuntimes[board.id] {
                        ObservedTerminalActivityStatus(runtime: runtime)
                    }
                })
        }
        .task {
            while !Task.isCancelled {
                refreshResourceUsage()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func usage(for board: BoardState) -> ProcessResourceUsage? {
        if let processID = controller.webRuntimes[board.id]?.webProcessIdentifier {
            return webUsage[processID]
        }
        return terminalUsage[board.id]
    }

    private func sharedWebBoardCount(for board: BoardState) -> Int {
        guard let processID = controller.webRuntimes[board.id]?.webProcessIdentifier else { return 0 }
        return controller.webRuntimes.values.count { $0.webProcessIdentifier == processID }
    }

    private func processLabel(for board: BoardState) -> String? {
        if let processID = controller.webRuntimes[board.id]?.webProcessIdentifier {
            return "Web PID \(processID)"
        }
        if let processGroupID = controller.terminalRuntimes[board.id]?.foregroundProcessGroupID {
            return "Terminal PGID \(processGroupID)"
        }
        return nil
    }

    private func processIdentifier(for board: BoardState) -> pid_t? {
        controller.webRuntimes[board.id]?.webProcessIdentifier
            ?? controller.terminalRuntimes[board.id]?.foregroundProcessGroupID
    }

    private func refreshResourceUsage() {
        var activeSamplerKeys = Set<String>()
        let webProcessIDs = Set(controller.webRuntimes.values.compactMap(\.webProcessIdentifier))
        webUsage = Dictionary(
            uniqueKeysWithValues: webProcessIDs.compactMap { processID in
                let key = "web:\(processID)"
                activeSamplerKeys.insert(key)
                return sampler.usage(key: key, pids: [processID]).map { (processID, $0) }
            })

        terminalUsage = Dictionary(
            uniqueKeysWithValues: controller.terminalRuntimes.compactMap { boardID, runtime in
                guard let processGroupID = runtime.foregroundProcessGroupID else { return nil }
                let pids = ProcessResourceSampler.processGroupPIDs(processGroupID)
                let key = "terminal:\(boardID)"
                activeSamplerKeys.insert(key)
                return sampler.usage(key: key, pids: pids).map { (boardID, $0) }
            })
        sampler.removeSamples(keeping: activeSamplerKeys)
    }
}

private struct ObservedWebActivityIcon: View {
    @ObservedObject var runtime: WebRuntime
    var body: some View {
        DenViews.WebActivityStateIcon(
            didTerminateContentProcess: runtime.didTerminateContentProcess,
            isLoading: runtime.isLoading, estimatedProgress: runtime.estimatedProgress,
            webProcessIsResponsive: runtime.webProcessIsResponsive)
    }
}

private struct ObservedTerminalActivityStatus: View {
    @ObservedObject var runtime: TerminalRuntime
    var body: some View {
        DenViews.TerminalActivityStatus(
            progressLabel: progressLabel, exitCode: runtime.lastCommandResult?.exitCode,
            durationNanos: runtime.lastCommandResult?.durationNanos, lastBellDate: runtime.lastBellDate)
    }
    private var progressLabel: String? {
        guard let state = runtime.progressState else { return nil }
        return switch state {
        case .remove: nil
        case .set: runtime.progressPercent.map { "\($0)%" } ?? "In progress"
        case .error: runtime.progressPercent.map { "Failed \($0)%" } ?? "Failed"
        case .indeterminate: "In progress"
        case .pause: runtime.progressPercent.map { "Paused \($0)%" } ?? "Paused"
        }
    }
}
