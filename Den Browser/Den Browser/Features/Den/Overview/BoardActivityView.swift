import AppKit
import GhosttyTerminal
import SwiftUI

struct BoardActivityView: View {
    let profileColor: Color

    @Environment(DenStore.self) private var store
    @State private var sampler = ProcessResourceSampler()
    @State private var webUsage: [pid_t: ProcessResourceUsage] = [:]
    @State private var terminalUsage: [UUID: ProcessResourceUsage] = [:]
    @State private var collapsedDeskIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Board Activity")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)

            ScrollView {
                if store.state.desks.allSatisfy({ $0.boards.isEmpty }) {
                    ContentUnavailableView(
                        "No Boards",
                        systemImage: "rectangle.stack",
                        description: Text("Board Activity appears after a Board is opened.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        BoardActivityTableHeader()

                        ForEach(store.state.desks) { desk in
                            if !desk.boards.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        toggleDesk(desk.id)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(
                                                systemName: collapsedDeskIDs.contains(desk.id)
                                                    ? "chevron.right" : "chevron.down"
                                            )
                                            .frame(width: 10)
                                            Text(desk.label)
                                                .fontWeight(.semibold)
                                            Text("\(desk.boards.count)")
                                                .foregroundStyle(.tertiary)
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(desk.label)
                                    .accessibilityValue(
                                        collapsedDeskIDs.contains(desk.id) ? "Collapsed" : "Expanded")

                                    if !collapsedDeskIDs.contains(desk.id) {
                                        ForEach(desk.boards) { board in
                                            BoardActivityRow(
                                                board: board,
                                                webRuntime: store.runtimes[board.id],
                                                terminalRuntime: store.terminalRuntimes[board.id],
                                                usage: usage(for: board),
                                                processLabel: processLabel(for: board),
                                                processIdentifier: processIdentifier(for: board),
                                                sharedWebBoardCount: sharedWebBoardCount(for: board),
                                                profileColor: profileColor,
                                                onOpen: { store.enterBoardFromActivity(board.id) },
                                                onRemove: { store.removeBoard(board.id) })
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .overlay(alignment: .topTrailing) {
            DenCloseButton(label: "Close Board Activity") {
                store.hideBoardActivity()
            }
            .padding(14)
        }
        .onExitCommand {
            store.hideBoardActivity()
        }
        .task {
            while !Task.isCancelled {
                refreshResourceUsage()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .accessibilityIdentifier("board-activity")
    }

    private func usage(for board: BoardState) -> ProcessResourceUsage? {
        if let processID = store.runtimes[board.id]?.webProcessIdentifier {
            return webUsage[processID]
        }
        return terminalUsage[board.id]
    }

    private func toggleDesk(_ deskID: UUID) {
        if !collapsedDeskIDs.insert(deskID).inserted {
            collapsedDeskIDs.remove(deskID)
        }
    }

    private func sharedWebBoardCount(for board: BoardState) -> Int {
        guard let processID = store.runtimes[board.id]?.webProcessIdentifier else { return 0 }
        return store.runtimes.values.count { $0.webProcessIdentifier == processID }
    }

    private func processLabel(for board: BoardState) -> String? {
        if let processID = store.runtimes[board.id]?.webProcessIdentifier {
            return "Web PID \(processID)"
        }
        if let processGroupID = store.terminalRuntimes[board.id]?.foregroundProcessGroupID {
            return "Terminal PGID \(processGroupID)"
        }
        return nil
    }

    private func processIdentifier(for board: BoardState) -> pid_t? {
        store.runtimes[board.id]?.webProcessIdentifier
            ?? store.terminalRuntimes[board.id]?.foregroundProcessGroupID
    }

    private func refreshResourceUsage() {
        let webProcessIDs = Set(store.runtimes.values.compactMap(\.webProcessIdentifier))
        webUsage = Dictionary(
            uniqueKeysWithValues: webProcessIDs.compactMap { processID in
                sampler.usage(key: "web:\(processID)", pids: [processID]).map { (processID, $0) }
            })

        terminalUsage = Dictionary(
            uniqueKeysWithValues: store.terminalRuntimes.compactMap { boardID, runtime in
                guard let processGroupID = runtime.foregroundProcessGroupID else { return nil }
                let pids = ProcessResourceSampler.processGroupPIDs(processGroupID)
                return sampler.usage(key: "terminal:\(boardID)", pids: pids).map { (boardID, $0) }
            })
    }
}

private struct BoardActivityRow: View {
    let board: BoardState
    let webRuntime: BoardRuntime?
    let terminalRuntime: TerminalRuntime?
    let usage: ProcessResourceUsage?
    let processLabel: String?
    let processIdentifier: pid_t?
    let sharedWebBoardCount: Int
    let profileColor: Color
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var isRemoveConfirmationPresented = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    boardStateIcon
                        .frame(width: 14)
                    Image(systemName: board.isTerminal ? "terminal" : "globe")
                        .foregroundStyle(board.isTerminal ? .orange : .blue)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(board.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let terminalRuntime {
                            TerminalActivityStatus(runtime: terminalRuntime)
                                .font(.caption.monospacedDigit())
                        }
                    }
                    Spacer(minLength: 8)
                    Text(cpuLabel)
                        .frame(width: BoardActivityColumns.cpu, alignment: .trailing)
                    Text(memoryLabel)
                        .frame(width: BoardActivityColumns.memory, alignment: .trailing)
                    Text(processDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: BoardActivityColumns.processText, alignment: .trailing)
                }
                .font(.caption.monospacedDigit())
                .padding(.leading, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open Board")
            .accessibilityIdentifier("board-activity-board.\(board.id.uuidString.lowercased())")

            if let processIdentifier {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(String(processIdentifier), forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: BoardActivityColumns.copyButton)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(board.isTerminal ? "Copy Terminal PGID" : "Copy Web PID")
            } else {
                Color.clear.frame(width: BoardActivityColumns.copyButton)
            }
        }
        .padding(.trailing, BoardActivityColumns.actionArea)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: DenRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.medium)
                .stroke(profileColor.opacity(0.18), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                isRemoveConfirmationPresented = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 22, height: 22)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(7)
            .accessibilityLabel("Remove \(board.displayName) Board")
        }
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            "Remove “\(board.displayName)” Board?",
            isPresented: $isRemoveConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Board", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                board.isTerminal
                    ? "This ends its live Terminal Session."
                    : "The Board will move to Recently Removed Boards.")
        }
    }

    private var detail: String {
        if board.isTerminal {
            return board.terminalWorkingDirectory
                ?? board.zellijSessionName
                ?? board.zmxSessionName
                ?? "Terminal"
        }
        return board.currentSheetURL?.host(percentEncoded: false)
            ?? board.currentSheetURL?.absoluteString
            ?? "Empty Web Board"
    }

    private var cpuLabel: String {
        guard let cpuPercent = usage?.cpuPercent else { return "—" }
        return "\(cpuPercent.formatted(.number.precision(.fractionLength(1))))%"
    }

    private var memoryLabel: String {
        guard let memoryBytes = usage?.memoryBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    private var processDescription: String {
        guard let processLabel else { return "—" }
        if sharedWebBoardCount > 1 {
            return "\(processLabel) · \(sharedWebBoardCount) Boards"
        }
        if let processCount = usage?.processCount, processCount > 1 {
            return "\(processLabel) · \(processCount) proc"
        }
        return processLabel
    }

    @ViewBuilder
    private var boardStateIcon: some View {
        if let webRuntime {
            WebActivityStateIcon(runtime: webRuntime)
        } else if terminalRuntime != nil {
            TerminalActivityStateIcon()
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Not active")
        }
    }
}

private enum BoardActivityColumns {
    static let cpu: CGFloat = 64
    static let memory: CGFloat = 76
    static let processText: CGFloat = 144
    static let copyButton: CGFloat = 20
    static let process: CGFloat = processText + copyButton + 8
    static let actionArea: CGFloat = 36
}

private struct BoardActivityTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 14)
            Color.clear.frame(width: 20)
            Text("Board")
            Spacer(minLength: 8)
            Text("CPU")
                .frame(width: BoardActivityColumns.cpu, alignment: .trailing)
            Text("Memory")
                .frame(width: BoardActivityColumns.memory, alignment: .trailing)
            Text("Process")
                .frame(width: BoardActivityColumns.process, alignment: .trailing)
        }
        .padding(.leading, 12)
        .padding(.trailing, BoardActivityColumns.actionArea)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

private struct WebActivityStateIcon: View {
    @ObservedObject var runtime: BoardRuntime

    @ViewBuilder
    var body: some View {
        if runtime.didTerminateContentProcess {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Content process ended")
        } else if runtime.isLoading {
            ProgressView(value: runtime.estimatedProgress)
                .controlSize(.small)
                .accessibilityLabel("Loading")
                .accessibilityValue("\(Int(runtime.estimatedProgress * 100)) percent")
        } else if runtime.webProcessIsResponsive == false {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Not responding")
        } else {
            Image(systemName: "circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Ready")
        }
    }
}

private struct TerminalActivityStateIcon: View {
    var body: some View {
        Image(systemName: "circle.fill")
            .foregroundStyle(.green)
            .accessibilityLabel("Running")
    }
}

private struct TerminalActivityStatus: View {
    @ObservedObject var runtime: TerminalRuntime

    var body: some View {
        HStack(spacing: 10) {
            if let progress = progressLabel {
                Text(progress)
            }
            if let result = runtime.lastCommandResult {
                Text(commandResultLabel(result))
                    .foregroundStyle(result.exitCode == 0 ? Color.secondary : Color.red)
            }
            if let lastBellDate = runtime.lastBellDate {
                Label(lastBellDate.formatted(date: .omitted, time: .shortened), systemImage: "bell")
                    .foregroundStyle(.secondary)
            }
        }
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

    private func commandResultLabel(_ result: TerminalRuntime.CommandResult) -> String {
        let seconds = Double(result.durationNanos) / 1_000_000_000
        let duration =
            seconds < 10
            ? seconds.formatted(.number.precision(.fractionLength(1)))
            : Int(seconds).description
        if let exitCode = result.exitCode {
            return "exit \(exitCode) · \(duration)s"
        }
        return "Finished · \(duration)s"
    }
}
