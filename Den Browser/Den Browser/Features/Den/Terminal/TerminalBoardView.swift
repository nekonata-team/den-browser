import GhosttyTerminal
import SwiftUI

struct TerminalBoardView: View {
    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let board: BoardState
    let isFocused: Bool
    let isDragging: Bool
    @ObservedObject var runtime: TerminalRuntime
    let profileColor: Color
    let width: Double
    let height: Double
    let isPointerFocusEnabled: Bool
    let onFocus: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            TerminalBoardSurface(
                terminalView: runtime.terminalView,
                isFocused: isFocused && !store.isDenMode && store.temporaryContext == nil,
                isHidden: store.isDrawerOpen || store.isOverviewPresented,
                isPointerFocusEnabled: isPointerFocusEnabled,
                onFocus: onFocus)
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-surface.\(board.id.uuidString.lowercased())")
        .clipShape(RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
                .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
        }
        .shadow(
            color: .black.opacity(isDragging ? 0.55 : (isFocused ? 0.42 : 0.30)),
            radius: isDragging ? 42 : (isFocused ? 34 : 24), x: 0, y: isDragging ? 28 : 22
        )
        .scaleEffect(isDragging && !shouldReduceMotion ? 1.02 : 1)
        .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: isFocused)
        .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: isDragging)
    }

    private var header: some View {
        HStack(spacing: DenLayout.outerInset) {
            dragHandle
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .help("Remove Board")
            .accessibilityLabel("Remove Board")
            .contextMenu { boardContextMenu }
        }
        .padding(.horizontal, DenLayout.chromeHorizontalPadding)
        .frame(height: DenLayout.boardHeaderHeight)
        .background(store.isDenMode && isFocused ? profileColor.opacity(0.12) : Color.clear)
        .background(.regularMaterial)
        .contextMenu { boardContextMenu }
    }

    private var dragHandle: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(board.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if isPointerFocusEnabled { onFocus() } }
        .gesture(
            DragGesture(coordinateSpace: .named(BoardStripCoordinateSpace.name))
                .onChanged { if isPointerFocusEnabled { onDragChanged($0) } }
                .onEnded { if isPointerFocusEnabled { onDragEnded($0) } }
        )
        .pointerStyle(isDragging ? .grabActive : .grabIdle)
        .help("Drag to move Board")
        .accessibilityLabel("Board: \(board.displayName)")
        .accessibilityIdentifier("board-header.\(board.id.uuidString.lowercased())")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    @ViewBuilder
    private var boardContextMenu: some View {
        Button {
            store.focusBoard(board.id)
            store.duplicateFocusedBoard()
        } label: {
            Label("Duplicate Terminal", systemImage: "plus.square.on.square")
        }
        Button {
            store.focusBoard(board.id)
            store.toggleFocusedBoardMaximized()
        } label: {
            Label(
                store.maximizedBoardID == board.id ? "Restore Board Size" : "Maximize Board",
                systemImage: store.maximizedBoardID == board.id
                    ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        Button {
            store.focusBoard(board.id)
            store.centerFocusedBoard()
        } label: {
            Label("Center Board", systemImage: "scope")
        }
        Divider()
        Button {
            store.focusBoard(board.id)
            store.moveFocusedBoardLeft()
        } label: {
            Label("Move Board Left", systemImage: "arrow.left")
        }
        .disabled(!store.canMoveBoard(board.id, by: -1))
        Button {
            store.focusBoard(board.id)
            store.moveFocusedBoardRight()
        } label: {
            Label("Move Board Right", systemImage: "arrow.right")
        }
        .disabled(!store.canMoveBoard(board.id, by: 1))
        if store.state.desks.count > 1 {
            Menu {
                ForEach(Array(store.state.desks.enumerated()), id: \.element.id) { entry in
                    if entry.element.id != boardDeskID {
                        Button("\(entry.offset + 1). \(entry.element.label)") {
                            store.focusBoard(board.id)
                            store.moveFocusedBoard(toDeskNumber: entry.offset + 1)
                        }
                    }
                }
            } label: {
                Label("Move to Desk", systemImage: "rectangle.stack")
            }
        }
        Divider()
        Button(role: .destructive) {
            store.removeBoard(board.id)
        } label: {
            Label("Remove Board", systemImage: "xmark")
        }
    }

    private var borderColor: Color {
        isFocused ? profileColor.opacity(0.75) : Color.primary.opacity(0.16)
    }

    private var boardDeskID: UUID? {
        store.boardIndices(for: board.id).map { store.state.desks[$0.desk].id }
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion)
    }
}

private struct TerminalBoardSurface: NSViewRepresentable {
    let terminalView: AppTerminalView
    let isFocused: Bool
    let isHidden: Bool
    let isPointerFocusEnabled: Bool
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AppTerminalView {
        context.coordinator.startRecognizing(view: terminalView, onFocus: onFocus)
        update(terminalView, coordinator: context.coordinator)
        return terminalView
    }

    func updateNSView(_ nsView: AppTerminalView, context: Context) {
        context.coordinator.onFocus = onFocus
        update(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: AppTerminalView, coordinator: Coordinator) {
        nsView.setSurfaceVisible(false)
        coordinator.stopRecognizing()
    }

    private func update(_ view: AppTerminalView, coordinator: Coordinator) {
        view.isHidden = isHidden
        view.setSurfaceVisible(!isHidden)
        coordinator.isEnabled = isPointerFocusEnabled
        guard isFocused else { return }
        Task { @MainActor [weak view] in
            await Task.yield()
            guard let view, let window = view.window,
                needsFirstResponderActivation(window.firstResponder, target: view)
            else { return }
            _ = window.makeFirstResponder(view)
        }
    }

    final class Coordinator: NSGestureRecognizer {
        fileprivate var onFocus: (() -> Void)?

        init() { super.init(target: nil, action: nil) }
        required init?(coder: NSCoder) { super.init(coder: coder) }

        func startRecognizing(view: AppTerminalView, onFocus: @escaping () -> Void) {
            self.onFocus = onFocus
            guard self.view == nil else { return }
            view.addGestureRecognizer(self)
        }

        override func mouseDown(with event: NSEvent) {
            if isEnabled { onFocus?() }
            state = .failed
        }

        func stopRecognizing() {
            view?.removeGestureRecognizer(self)
            onFocus = nil
        }
    }
}
