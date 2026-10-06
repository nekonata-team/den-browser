import AppKit
import Combine
import DenDomain
import SFSafeSymbols
import SwiftUI

struct InspectionBoardView: View {
    @Environment(DenStore.self) private var store
    @Environment(DenViewModel.self) private var viewModel

    let board: BoardState
    let isFocused: Bool
    let focusRequest: BoardFocusRequest?
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
    @State private var expandedNodeIDs: Set<String> = []
    @State private var loadedChildren: [String: [InspectionDOMNode]] = [:]
    @State private var loadingNodeIDs: Set<String> = []
    @State private var observedInspectionPageGeneration = 0
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var targetBoard: BoardState? { store.board(for: targetBoardID) }
    private var targetRuntime: WebBoardRuntime? { store.webRuntimes[targetBoardID] }
    private var inspectionHighlightColor: ProfileRGB? { profileRGB(from: profileColor) }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .modifier(
            BoardSurfaceModifier(
                boardID: board.id,
                isFocused: isFocused,
                isDragging: isDragging,
                profileColor: profileColor,
                width: width,
                height: height,
                isFocusModeDeemphasized: viewModel.isFocusModePresented && !isFocused,
                isFocusModeFocused: viewModel.isFocusModePresented && isFocused,
                differentiateWithoutColor: differentiateWithoutColor,
                shouldReduceMotion: false
            )
        )
        .background {
            InspectionBoardFocusSurface(request: focusRequest)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task(id: targetRuntime?.id) {
            targetRuntime?.startInspectionCollection(highlightColor: inspectionHighlightColor)
        }
        .task(id: isVisibleInViewport ? targetRuntime?.id : nil) {
            guard isVisibleInViewport else { return }
            while !Task.isCancelled {
                guard let targetRuntime else { return }
                let generation = targetRuntime.inspectionPageGeneration
                let nextSnapshot = await targetRuntime.readInspectionSnapshot()
                let children = await targetRuntime.readInspectionChildren(for: Array(loadedChildren.keys))
                guard !Task.isCancelled else { return }
                if generation == targetRuntime.inspectionPageGeneration {
                    snapshot = nextSnapshot
                    for (nodeID, refreshedChildren) in children where loadedChildren[nodeID] != nil {
                        loadedChildren[nodeID] = refreshedChildren
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onChange(of: snapshot.treePath.map(\.id)) { _, path in
            if path.isEmpty {
                expandedNodeIDs.removeAll()
                loadedChildren.removeAll()
                loadingNodeIDs.removeAll()
                return
            }
            expandedNodeIDs.formUnion(path.dropLast())
        }
        .onChange(of: inspectionHighlightColor) { _, color in
            targetRuntime?.setInspectionHighlightColor(color)
        }
        .onReceive(
            targetRuntime?.inspectionPageGenerationPublisher ?? Just(0).eraseToAnyPublisher()
        ) { generation in
            guard generation != observedInspectionPageGeneration else { return }
            observedInspectionPageGeneration = generation
            snapshot = .empty
            expandedNodeIDs.removeAll()
            loadedChildren.removeAll()
            loadingNodeIDs.removeAll()
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
                },
                leadingContent: {
                    Image(systemSymbol: .magnifyingglass)
                        .foregroundStyle(profileColor)
                }
            )

            Button(action: onRemove) {
                Image(systemSymbol: .xmark)
                    .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove Inspection Board")
        }
        .padding(.horizontal, DenLayout.chromeHorizontalPadding)
        .frame(height: DenLayout.boardHeaderHeight)
        .background(viewModel.isDenMode && isFocused ? profileColor.opacity(0.12) : Color.clear)
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
                    Button {
                        targetRuntime?.beginInspectionPicking(highlightColor: inspectionHighlightColor)
                    } label: {
                        Label("Pick Element", systemSymbol: .pointerArrowSquare)
                            .labelStyle(.iconOnly)
                            .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                    }
                    .buttonStyle(.glass)
                    .tint(snapshot.isPicking ? profileColor : nil)
                    .disabled(targetRuntime?.webView.url == nil)
                    .help("Pick an element in the target Web Board's Current Sheet")
                    .accessibilityValue(snapshot.isPicking ? "Picking" : "Ready")
                    .accessibilityHint("Choose an element in the target Web Board's Current Sheet")

                    Spacer()
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        domTree
                        Divider()
                        selectionDetails
                        consoleDetails
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            ContentUnavailableView(
                "Target Web Board Unavailable",
                systemSymbol: .globe,
                description: Text("The linked Web Board or its Current Sheet is not available.")
            )
        }
    }

    private var domTree: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DOM").font(.headline)
            if let root = snapshot.treePath.first {
                domNodeBranch(root, depth: 0)
            } else {
                Text("Pick an element to show its path in the page DOM.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("inspection-dom-tree")
    }

    private func domNodeBranch(_ node: InspectionDOMNode, depth: Int) -> InspectionDOMBranch {
        InspectionDOMBranch(
            node: node,
            depth: depth,
            isExpanded: expandedNodeIDs.contains(node.id),
            isLoading: loadingNodeIDs.contains(node.id),
            isSelected: node.id == snapshot.treePath.last?.id,
            profileColor: profileColor,
            children: children(for: node),
            hasMoreChildren: children(for: node).count < node.childCount,
            label: InspectionDOMSyntaxLabel(node: node),
            makeBranch: { child, childDepth in domNodeBranch(child, depth: childDepth) },
            onToggle: { toggleDOMNode(node) },
            onSelect: { targetRuntime?.selectInspectionNode(node.id) },
            onHover: { targetRuntime?.highlightInspectionNode($0 ? node.id : nil) }
        )
    }

    private func children(for node: InspectionDOMNode) -> [InspectionDOMNode] {
        if let loaded = loadedChildren[node.id] { return loaded }
        guard let index = snapshot.treePath.firstIndex(where: { $0.id == node.id }),
            snapshot.treePath.indices.contains(index + 1)
        else { return [] }
        return [snapshot.treePath[index + 1]]
    }

    private func toggleDOMNode(_ node: InspectionDOMNode) {
        if expandedNodeIDs.contains(node.id),
            loadedChildren[node.id] != nil || children(for: node).count >= node.childCount
        {
            expandedNodeIDs.remove(node.id)
            return
        }
        expandedNodeIDs.insert(node.id)
        guard loadedChildren[node.id] == nil, !loadingNodeIDs.contains(node.id) else { return }
        loadingNodeIDs.insert(node.id)
        Task {
            guard let targetRuntime else {
                loadingNodeIDs.remove(node.id)
                return
            }
            let generation = targetRuntime.inspectionPageGeneration
            let children = await targetRuntime.readInspectionChildren(for: node.id)
            guard targetRuntime.isInspectionActive,
                generation == targetRuntime.inspectionPageGeneration
            else { return }
            loadedChildren[node.id] = children
            loadingNodeIDs.remove(node.id)
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
                Text("Page console output and JavaScript errors appear here.")
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

private struct InspectionBoardFocusSurface: NSViewRepresentable {
    let request: BoardFocusRequest?

    func makeNSView(context _: Context) -> SurfaceHost<BoardFocusRequest, InspectionBoardInputView> {
        let inputView = InspectionBoardInputView(frame: .zero)
        let host = SurfaceHost<BoardFocusRequest, InspectionBoardInputView>(content: inputView)
        host.update(
            request: request,
            onReady: { window in
                guard
                    needsFirstResponderActivation(window.firstResponder, target: inputView)
                else { return true }
                return window.makeFirstResponder(inputView)
            })
        return host
    }

    func updateNSView(
        _ host: SurfaceHost<BoardFocusRequest, InspectionBoardInputView>,
        context _: Context
    ) {
        let inputView = host.content
        host.update(
            request: request,
            onReady: { window in
                guard
                    needsFirstResponderActivation(window.firstResponder, target: inputView)
                else { return true }
                return window.makeFirstResponder(inputView)
            })
    }
}

private final class InspectionBoardInputView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let movesBackward = InspectionBoardKeyTraversal.movesBackward(for: event) else { return }
        if movesBackward {
            window?.selectPreviousKeyView(self)
        } else {
            window?.selectNextKeyView(self)
        }
    }
}

enum InspectionBoardKeyTraversal {
    static func movesBackward(for event: NSEvent) -> Bool? {
        guard ShortcutKey(event: event) == .tab || event.characters == "\u{19}" else { return nil }
        return event.specialKey == .backTab
            || event.characters == "\u{19}"
            || event.modifierFlags.contains(.shift)
    }
}

private struct InspectionDOMBranch: View {
    let node: InspectionDOMNode
    let depth: Int
    let isExpanded: Bool
    let isLoading: Bool
    let isSelected: Bool
    let profileColor: Color
    let children: [InspectionDOMNode]
    let hasMoreChildren: Bool
    let label: InspectionDOMSyntaxLabel
    let makeBranch: (InspectionDOMNode, Int) -> InspectionDOMBranch
    let onToggle: () -> Void
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Button(action: onToggle) {
                    Image(systemSymbol: disclosureSymbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 16)
                }
                .buttonStyle(.plain)
                .disabled(node.childCount == 0)
                .accessibilityLabel(disclosureLabel)
                Button(action: onSelect) {
                    label
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(node.tag) DOM element")
                .accessibilityIdentifier("inspection-dom-node-\(node.id)")
                .padding(.horizontal, 4)
                .background(isSelected ? profileColor.opacity(0.2) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 3).stroke(profileColor.opacity(0.6), lineWidth: 1)
                    }
                }
                .onHover(perform: onHover)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 12)

            if isExpanded {
                if isLoading {
                    ProgressView().controlSize(.small).padding(.leading, CGFloat(depth + 1) * 12)
                }
                ForEach(children) { child in
                    makeBranch(child, depth + 1)
                }
            }
        }
    }

    private var disclosureSymbol: SFSymbol {
        if node.childCount == 0 { return .chevronRight }
        if isLoading { return .ellipsis }
        if isExpanded && hasMoreChildren { return .plus }
        return isExpanded ? .chevronDown : .chevronRight
    }

    private var disclosureLabel: String {
        if isExpanded && hasMoreChildren { return "Load remaining child elements" }
        return isExpanded ? "Collapse child elements" : "Expand child elements"
    }
}

private struct InspectionDOMSyntaxLabel: View {
    let node: InspectionDOMNode

    var body: some View {
        HStack(spacing: 0) {
            Text("<").foregroundStyle(.secondary)
            Text(node.tag).foregroundStyle(.orange)
            ForEach(node.attributes) { attribute in
                Text(" ").foregroundStyle(.secondary)
                Text(attribute.name).foregroundStyle(.blue)
                Text("=\"").foregroundStyle(.secondary)
                Text(attribute.value).foregroundStyle(.green)
                Text("\"").foregroundStyle(.secondary)
            }
            if node.childCount == 0 {
                if node.text.isEmpty {
                    Text(" />").foregroundStyle(.secondary)
                } else {
                    Text(">").foregroundStyle(.secondary)
                    Text(node.text).foregroundStyle(.primary.opacity(0.75))
                    Text("</\(node.tag)>").foregroundStyle(.orange)
                }
            } else {
                Text(">").foregroundStyle(.secondary)
            }
        }
    }
}
