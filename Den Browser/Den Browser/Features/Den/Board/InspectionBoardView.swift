import SFSafeSymbols
import SwiftUI

struct InspectionBoardView: View {
    @Environment(DenStore.self) private var store

    let board: BoardState
    let isFocused: Bool
    let isDragging: Bool
    let isPointerFocusEnabled: Bool
    let profileColor: Color
    let width: Double
    let height: Double
    let isVisibleInViewport: Bool
    let targetBoardID: UUID
    let onFocus: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    @State private var snapshot = InspectionPageSnapshot.empty
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var targetBoard: BoardState? { store.board(for: targetBoardID) }
    private var targetRuntime: BoardRuntime? { store.runtimes[targetBoardID] }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
        .modifier(
            BoardSurfaceModifier(
                boardID: board.id,
                isFocused: isFocused,
                isDragging: isDragging,
                profileColor: profileColor,
                width: width,
                height: height,
                isFocusModeDeemphasized: store.isFocusModePresented && !isFocused,
                isFocusModeFocused: store.isFocusModePresented && isFocused,
                differentiateWithoutColor: differentiateWithoutColor,
                shouldReduceMotion: false
            )
        )
        .task(id: isVisibleInViewport) {
            guard isVisibleInViewport else { return }
            while !Task.isCancelled {
                if let targetRuntime, targetRuntime.isInspectionActive {
                    snapshot = await targetRuntime.readInspectionSnapshot()
                } else {
                    snapshot = .empty
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private var header: some View {
        HStack(spacing: DenLayout.outerInset) {
            BoardDragHeader(
                board: board,
                isFocused: isFocused,
                isDragging: isDragging,
                isPointerFocusEnabled: isPointerFocusEnabled,
                onFocus: onFocus,
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded,
                onMoveLeft: {
                    store.focusBoard(board.id)
                    store.moveFocusedBoardLeft()
                },
                onMoveRight: {
                    store.focusBoard(board.id)
                    store.moveFocusedBoardRight()
                }
            ) {
                Image(systemSymbol: .magnifyingglass)
                    .foregroundStyle(profileColor)
            }

            Button(action: onRemove) {
                Image(systemSymbol: .xmark)
                    .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove Inspection Board")
        }
        .padding(.horizontal, DenLayout.chromeHorizontalPadding)
        .frame(height: DenLayout.boardHeaderHeight)
        .background(.regularMaterial)
        .contextMenu {
            if targetBoard != nil {
                Button("Focus Target Web Board") { store.focusBoard(targetBoardID, exitsDenMode: true) }
            }
            Button("Copy Board ID") { store.copyBoardID(board.id) }
            Divider()
            Button("Remove Inspection Board", role: .destructive, action: onRemove)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let targetBoard, targetBoard.isWeb {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Target: \(targetBoard.displayName)", systemSymbol: .globe)
                        .lineLimit(1)
                    Spacer()
                    Button("Focus") { store.focusBoard(targetBoardID, exitsDenMode: true) }
                        .buttonStyle(.borderless)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button(
                        snapshot.isPicking ? "Picking…" : (snapshot.selection == nil ? "Pick Element" : "Pick Another")
                    ) {
                        targetRuntime?.beginInspectionPicking()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(targetRuntime?.webView.url == nil)
                    .accessibilityHint("Choose an element in the target Web Board's Current Sheet")

                    if targetRuntime?.isInspectionActive == true {
                        Button(action: {
                            targetRuntime?.stopInspection()
                            snapshot = .empty
                        }) {
                            Label("Stop", systemSymbol: .stopCircle)
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                }

                if snapshot.isPicking {
                    Text("Click an element in the target Web Board.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        selectionDetails
                        consoleDetails
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            ContentUnavailableView(
                "Target Web Board Unavailable",
                systemImage: "globe.badge.chevron.backward",
                description: Text("The linked Web Board or its Current Sheet is not available.")
            )
        }
    }

    @ViewBuilder
    private var selectionDetails: some View {
        if let selection = snapshot.selection {
            VStack(alignment: .leading, spacing: 5) {
                Text("Selected Element").font(.headline)
                Text("<\(selection.tag)>  \(selection.id.isEmpty ? "" : "#\(selection.id)")")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if !selection.className.isEmpty { detailLine("Class", selection.className) }
                if !selection.text.isEmpty { detailLine("Text", selection.text) }
                if !selection.ariaLabel.isEmpty { detailLine("ARIA label", selection.ariaLabel) }
                if !selection.role.isEmpty { detailLine("ARIA role", selection.role) }
                if !selection.attributes.isEmpty {
                    detailLine("ARIA / attributes", selection.attributes.joined(separator: " · "))
                }
                if !selection.labels.isEmpty { detailLine("Labels", selection.labels.joined(separator: " · ")) }
                if !selection.ancestors.isEmpty {
                    Text("Ancestors").font(.caption.weight(.semibold))
                    ForEach(Array(selection.ancestors.enumerated()), id: \.offset) { _, ancestor in
                        Text(ancestor).font(.system(.caption2, design: .monospaced))
                    }
                }
            }
            .accessibilityIdentifier("inspection-selection")
        } else {
            Text("No element selected yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("inspection-selection-empty")
        }
    }

    private var consoleDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Page Console").font(.headline)
                Spacer()
                Text("\(snapshot.events.count)").font(.caption).foregroundStyle(.secondary)
            }
            if snapshot.events.isEmpty {
                Text("Page console output and JavaScript errors appear after inspection starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.events.suffix(40).reversed()) { event in
                    HStack(alignment: .top, spacing: 6) {
                        Text(event.level.uppercased())
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                            .foregroundStyle(event.level == "error" || event.level == "rejection" ? .red : .secondary)
                            .frame(width: 68, alignment: .leading)
                        Text(event.message)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Text(event.time).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("inspection-console")
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold))
            Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }
}
