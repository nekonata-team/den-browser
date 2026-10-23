public import AppKit
public import DenDomain
public import DenModels
import SFSafeSymbols
public import SwiftUI

public struct BoardActivityView<Row: View>: View {
    let profileColor: Color

    private let row: (BoardState) -> Row
    @Environment(DenWindowModel.self) private var windowModel
    @State private var collapsedDeskIDs: Set<DeskID> = []

    public init(profileColor: Color, @ViewBuilder row: @escaping (BoardState) -> Row) {
        self.profileColor = profileColor
        self.row = row
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Board Activity")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)

            ScrollView {
                if windowModel.desks.desks.allSatisfy({ $0.boards.isEmpty }) {
                    ContentUnavailableView(
                        "No Boards",
                        systemSymbol: .rectangleStack,
                        description: Text("Board Activity appears after a Board is opened.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        BoardActivityTableHeader()

                        ForEach(windowModel.desks.desks) { desk in
                            if !desk.boards.isEmpty {
                                BoardActivityDeskSection(
                                    desk: desk,
                                    isCollapsed: collapsedDeskIDs.contains(desk.id),
                                    profileColor: profileColor,
                                    onToggle: { toggleDesk(desk.id) },
                                    rowContent: { board in
                                        row(board)
                                    }
                                )
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
                windowModel.hideBoardActivity()
            }
            .padding(14)
        }
        .onExitCommand {
            windowModel.hideBoardActivity()
        }
        .accessibilityIdentifier("board-activity")
    }

    private func toggleDesk(_ deskID: DeskID) {
        if !collapsedDeskIDs.insert(deskID).inserted {
            collapsedDeskIDs.remove(deskID)
        }
    }
}

private struct BoardActivityDeskSection<RowContent: View>: View {
    let desk: DeskState
    let isCollapsed: Bool
    let profileColor: Color
    let onToggle: () -> Void
    @ViewBuilder let rowContent: (BoardState) -> RowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemSymbol: isCollapsed ? .chevronRight : .chevronDown)
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
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")

            if !isCollapsed {
                ForEach(desk.boards) { board in
                    rowContent(board)
                }
            }
        }
    }
}

public struct BoardActivityRow<StateIcon: View, Status: View>: View {
    let board: BoardState
    private let stateIcon: StateIcon
    private let status: Status
    let usage: ProcessResourceUsage?
    let processLabel: String?
    let processIdentifier: pid_t?
    let sharedWebBoardCount: Int
    let profileColor: Color
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var isRemoveConfirmationPresented = false

    public init(
        board: BoardState, usage: ProcessResourceUsage?, processLabel: String?, processIdentifier: Int32?,
        sharedWebBoardCount: Int, profileColor: Color, onOpen: @escaping () -> Void, onRemove: @escaping () -> Void,
        @ViewBuilder stateIcon: () -> StateIcon, @ViewBuilder status: () -> Status
    ) {
        self.board = board
        self.usage = usage
        self.processLabel = processLabel
        self.processIdentifier = processIdentifier
        self.sharedWebBoardCount = sharedWebBoardCount
        self.profileColor = profileColor
        self.onOpen = onOpen
        self.onRemove = onRemove
        self.stateIcon = stateIcon()
        self.status = status()
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    boardStateIcon
                        .frame(width: 14)
                    Image(systemSymbol: boardSymbol(for: board.kind))
                        .foregroundStyle(
                            board.isInspection || board.isTutorial
                                ? .purple
                                : (board.isTerminal ? .orange : .blue)
                        )
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(board.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        status.font(.caption.monospacedDigit())
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
            .accessibilityIdentifier("board-activity-board.\(board.id.rawValue.uuidString.lowercased())")

            if let processIdentifier {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(String(processIdentifier), forType: .string)
                } label: {
                    Image(systemSymbol: .documentOnDocument)
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
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: DenRadius.small))
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.small)
                .stroke(profileColor.opacity(0.18), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                isRemoveConfirmationPresented = true
            } label: {
                Image(systemSymbol: .xmark)
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
        if board.isInspection {
            return board.sideBoardTargetBoardID.map { "Target Board \($0.rawValue.uuidString.prefix(8))" }
                ?? "Inspection Board"
        } else if board.isTutorial {
            return "Interactive tutorial"
        }
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

    private var boardStateIcon: some View { stateIcon }
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

public struct WebActivityStateIcon: View {
    let didTerminateContentProcess: Bool
    let isLoading: Bool
    let estimatedProgress: Double
    let webProcessIsResponsive: Bool?

    public init(
        didTerminateContentProcess: Bool, isLoading: Bool, estimatedProgress: Double, webProcessIsResponsive: Bool?
    ) {
        self.didTerminateContentProcess = didTerminateContentProcess
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.webProcessIsResponsive = webProcessIsResponsive
    }

    @ViewBuilder
    public var body: some View {
        if didTerminateContentProcess {
            Image(systemSymbol: .xmarkCircleFill)
                .foregroundStyle(.red)
                .accessibilityLabel("Content process ended")
        } else if isLoading {
            ProgressView(value: estimatedProgress)
                .controlSize(.small)
                .accessibilityLabel("Loading")
                .accessibilityValue("\(Int(estimatedProgress * 100)) percent")
        } else if webProcessIsResponsive == false {
            Image(systemSymbol: .exclamationmarkCircleFill)
                .foregroundStyle(.red)
                .accessibilityLabel("Not responding")
        } else {
            Image(systemSymbol: .circleFill)
                .foregroundStyle(.green)
                .accessibilityLabel("Ready")
        }
    }
}

public struct TerminalActivityStateIcon: View {
    public init() {}
    public var body: some View {
        Image(systemSymbol: .circleFill)
            .foregroundStyle(.green)
            .accessibilityLabel("Running")
    }
}

public struct TerminalActivityStatus: View {
    let progressLabel: String?
    let exitCode: Int?
    let durationNanos: UInt64?
    let lastBellDate: Date?

    public init(progressLabel: String?, exitCode: Int?, durationNanos: UInt64?, lastBellDate: Date?) {
        self.progressLabel = progressLabel
        self.exitCode = exitCode
        self.durationNanos = durationNanos
        self.lastBellDate = lastBellDate
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let progress = progressLabel {
                Text(progress)
            }
            if let durationNanos {
                Text(commandResultLabel(durationNanos: durationNanos))
                    .foregroundStyle(exitCode == 0 ? Color.secondary : Color.red)
            }
            if let lastBellDate = lastBellDate {
                Label(lastBellDate.formatted(date: .omitted, time: .shortened), systemSymbol: .bell)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func commandResultLabel(durationNanos: UInt64) -> String {
        let seconds = Double(durationNanos) / 1_000_000_000
        let duration =
            seconds < 10
            ? seconds.formatted(.number.precision(.fractionLength(1)))
            : Int(seconds).description
        if let exitCode = exitCode {
            return "exit \(exitCode) · \(duration)s"
        }
        return "Finished · \(duration)s"
    }
}

public struct InactiveActivityStateIcon: View {
    public init() {}
    public var body: some View {
        Image(systemSymbol: .circle).foregroundStyle(.secondary).accessibilityLabel("Not active")
    }
}
