import DenDomain
import DenModels
import DenViews
import GhosttyTerminal
import SwiftUI

struct BoardActivityView: View {
    let profileColor: Color
    @Environment(DenWindowModel.self) private var windowModel
    private let resources: DenProfileResources
    private let remove: (BoardID) -> Void
    @State private var sampling: BoardActivitySampling

    init(profileColor: Color, resources: DenProfileResources, remove: @escaping (BoardID) -> Void) {
        self.profileColor = profileColor
        self.resources = resources
        self.remove = remove
        _sampling = State(initialValue: BoardActivitySampling(resources: resources))
    }

    var body: some View {
        DenViews.BoardActivityView(profileColor: profileColor) { board in
            DenViews.BoardActivityRow(
                board: board, usage: sampling.usage(for: board),
                processLabel: sampling.processLabel(for: board),
                processIdentifier: sampling.processIdentifier(for: board),
                sharedWebBoardCount: sampling.sharedWebBoardCount(for: board), profileColor: profileColor,
                onOpen: { windowModel.enterBoardFromActivity(board.id) },
                onRemove: { remove(board.id) },
                stateIcon: {
                    if let runtime = resources.webRuntimes[board.id] {
                        ObservedWebActivityIcon(runtime: runtime)
                    } else if resources.terminalRuntimes[board.id] != nil {
                        DenViews.TerminalActivityStateIcon()
                    } else {
                        DenViews.InactiveActivityStateIcon()
                    }
                },
                status: {
                    if let runtime = resources.terminalRuntimes[board.id] {
                        ObservedTerminalActivityStatus(runtime: runtime)
                    }
                })
        }
        .task {
            await sampling.run()
        }
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
