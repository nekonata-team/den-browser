import GhosttyTerminal
import SFSafeSymbols
import SwiftUI

struct TerminalBoardView: View {
    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let board: BoardState
    let isFocused: Bool
    let focusRequest: BoardFocusRequest?
    let isDragging: Bool
    @ObservedObject var runtime: TerminalRuntime
    let profileColor: Color
    let width: Double
    let height: Double
    let isPointerFocusEnabled: Bool
    var isVisibleInViewport: Bool = true
    let onFocus: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    @State private var isMagnifying = false
    @State private var appliedFontSizeSteps = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            TerminalBoardSurface(
                terminalView: runtime.terminalView,
                onSurfaceVisibilityChange: { runtime.setSurfaceVisible($0) },
                isHidden: !isVisibleInViewport || store.isOverviewPresented
                    || (store.isDrawerOpen && preferences.drawerStyle == .bottom),
                focusRequest: focusRequest,
                onSurfaceReady: { window in
                    guard
                        needsFirstResponderActivation(
                            window.firstResponder,
                            target: runtime.terminalView
                        )
                    else { return true }
                    return window.makeFirstResponder(runtime.terminalView)
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in
                        guard isPointerFocusEnabled else { return }
                        onFocus()
                    }
            )
            .simultaneousGesture(
                MagnifyGesture(minimumScaleDelta: 0.01)
                    .onChanged { value in
                        guard isPointerFocusEnabled else { return }
                        if !isMagnifying {
                            isMagnifying = true
                            appliedFontSizeSteps = 0
                            onFocus()
                        }

                        let targetSteps = Int(
                            ((value.magnification - 1) / 0.1).rounded(.towardZero)
                        )
                        let delta = targetSteps - appliedFontSizeSteps
                        guard delta != 0 else { return }
                        appliedFontSizeSteps += runtime.adjustFontSize(by: delta)
                    }
                    .onEnded { _ in
                        isMagnifying = false
                        appliedFontSizeSteps = 0
                    }
            )
            .blur(radius: isFocusModeDeemphasized ? DenLayout.focusModeBlurRadius : 0)
        }
        .modifier(
            BoardSurfaceModifier(
                boardID: board.id,
                isFocused: isFocused,
                isDragging: isDragging,
                profileColor: profileColor,
                width: width,
                height: height,
                isFocusModeDeemphasized: isFocusModeDeemphasized,
                isFocusModeFocused: isFocusModeFocused,
                differentiateWithoutColor: differentiateWithoutColor,
                shouldReduceMotion: shouldReduceMotion
            )
        )
    }

    private var isFocusModeDeemphasized: Bool {
        store.isFocusModePresented && !isFocused && !store.isDeskFilterPresented
    }

    private var isFocusModeFocused: Bool {
        store.isFocusModePresented && isFocused
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
                    Image(
                        systemSymbol: board.isZellij
                            ? .rectangle3Group
                            : (board.isZmx ? .arrowTrianglehead2ClockwiseRotate90 : .appleTerminal)
                    )
                    .foregroundStyle(.secondary)
                }
            )
            Button(action: onRemove) {
                Image(systemSymbol: .xmark)
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
        .modifier(
            BoardHeaderCenteringModifier(
                boardID: board.id,
                isEnabled: isPointerFocusEnabled
            )
        )
        .contextMenu { boardContextMenu }
    }

    @ViewBuilder
    private var boardContextMenu: some View {
        Button {
            store.focusBoard(board.id)
            store.duplicateFocusedBoard()
        } label: {
            Label(
                board.isZellij
                    ? "Duplicate Zellij Board"
                    : (board.isZmx ? "Duplicate zmx Board…" : "Duplicate Terminal Board"),
                systemSymbol: .plusSquareOnSquare)
        }
        Button {
            store.focusBoard(board.id)
            store.showSaveEssentialPanel(for: board)
        } label: {
            Label("Save as Essential…", systemSymbol: .sparkles)
        }
        Button {
            store.copyBoardID(board.id)
        } label: {
            Label("Copy Board ID", systemSymbol: .documentOnDocument)
        }
        Button {
            store.focusBoard(board.id)
            store.toggleFocusedBoardMaximized()
        } label: {
            Label(
                store.maximizedBoardID == board.id ? "Restore Board Size" : "Maximize Board",
                systemSymbol: store.maximizedBoardID == board.id
                    ? .arrowDownRightAndArrowUpLeft : .arrowUpLeftAndArrowDownRight)
        }
        Button {
            store.focusBoard(board.id)
            store.centerFocusedBoard()
        } label: {
            Label("Center Board", systemSymbol: .scope)
        }
        if board.isZmx {
            Button {
                store.focusBoard(board.id)
                store.showZmxSessions(selectedSessionName: board.zmxSessionName)
            } label: {
                Label("zmx Sessions…", systemSymbol: .arrowTrianglehead2ClockwiseRotate90)
            }
        }
        Divider()
        Button {
            store.focusBoard(board.id)
            store.adjustFocusedBoardContentSize(by: 1)
        } label: {
            Label("Increase Font Size", systemSymbol: .plus)
        }
        Button {
            store.focusBoard(board.id)
            store.adjustFocusedBoardContentSize(by: -1)
        } label: {
            Label("Decrease Font Size", systemSymbol: .minus)
        }
        Button {
            store.focusBoard(board.id)
            store.resetFocusedBoardContentSize()
        } label: {
            Label("Reset Font Size", systemSymbol: .arrowCounterclockwise)
        }
        Divider()
        Button {
            store.focusBoard(board.id)
            store.moveFocusedBoardLeft()
        } label: {
            Label("Move Board Left", systemSymbol: .arrowLeft)
        }
        .disabled(!store.canMoveBoard(board.id, by: -1))
        Button {
            store.focusBoard(board.id)
            store.moveFocusedBoardRight()
        } label: {
            Label("Move Board Right", systemSymbol: .arrowRight)
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
                Label("Move to Desk", systemSymbol: .rectangleStack)
            }
        }
        Divider()
        Button(role: .destructive) {
            store.removeBoard(board.id)
        } label: {
            Label("Remove Board", systemSymbol: .xmark)
        }
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
    let onSurfaceVisibilityChange: (Bool) -> Void
    let isHidden: Bool
    let focusRequest: BoardFocusRequest?
    let onSurfaceReady: (NSWindow) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SurfaceHost<BoardFocusRequest, AppTerminalView> {
        let host = SurfaceHost<BoardFocusRequest, AppTerminalView>(content: terminalView)
        update(terminalView, coordinator: context.coordinator)
        host.update(request: focusRequest, onReady: onSurfaceReady)
        return host
    }

    func updateNSView(
        _ nsView: SurfaceHost<BoardFocusRequest, AppTerminalView>,
        context: Context
    ) {
        update(terminalView, coordinator: context.coordinator)
        nsView.update(request: focusRequest, onReady: onSurfaceReady)
    }

    static func dismantleNSView(
        _ nsView: SurfaceHost<BoardFocusRequest, AppTerminalView>,
        coordinator: Coordinator
    ) {
        coordinator.onSurfaceVisibilityChange?(false)
        coordinator.onSurfaceVisibilityChange = nil
    }

    private func update(_ view: AppTerminalView, coordinator: Coordinator) {
        coordinator.onSurfaceVisibilityChange = onSurfaceVisibilityChange
        view.isHidden = isHidden
        onSurfaceVisibilityChange(!isHidden)
    }

    final class Coordinator {
        fileprivate var onSurfaceVisibilityChange: ((Bool) -> Void)?
    }
}
