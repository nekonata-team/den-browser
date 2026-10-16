import DenDesign
import DenDomain
import DenPresentationModels
import GhosttyTerminal
import SFSafeSymbols
import SwiftUI

struct TerminalBoardView: View {
    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(DeskFilterModel.self) private var deskFilter
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
                onBeforeHide: {
                    guard controller.terminalRuntimes[board.id] === runtime else { return }
                    controller.facingCapture.captureTerminal(
                        boardID: board.id, terminalView: runtime.terminalView)
                },
                isHidden: !isSurfaceVisible,
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

    private var isSurfaceVisible: Bool {
        isVisibleInViewport && !windowModel.isOverviewPresented
            && !(windowModel.isDrawerOpen && preferences.drawerStyle == .bottom)
    }

    private var isFocusModeDeemphasized: Bool {
        windowModel.isFocusModePresented && !isFocused && !deskFilter.isPresented
    }

    private var isFocusModeFocused: Bool {
        windowModel.isFocusModePresented && isFocused
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
                    controller.focusBoard(board.id)
                    controller.moveFocusedBoardLeft()
                },
                onMoveRight: {
                    controller.focusBoard(board.id)
                    controller.moveFocusedBoardRight()
                },
                leadingContent: {
                    Image(systemSymbol: boardSymbol(for: board.kind))
                        .foregroundStyle(.secondary)
                }
            )
            HStack(spacing: 2) {
                if preferences.rememberBoardInputMethod,
                    let label = controller.inputSourceTracker.shortLabel(for: board.id)
                {
                    BoardInputSourceBadge(label: label, isFocused: isFocused)
                }

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
        }
        .padding(.horizontal, DenLayout.chromeHorizontalPadding)
        .frame(height: DenLayout.boardHeaderHeight)
        .background(windowModel.isDenMode && isFocused ? profileColor.opacity(0.12) : Color.clear)
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
            controller.focusBoard(board.id)
            controller.duplicateFocusedBoard()
        } label: {
            Label(
                board.isZellij
                    ? "Duplicate Zellij Board"
                    : (board.isZmx ? "Duplicate zmx Board…" : "Duplicate Terminal Board"),
                systemSymbol: .plusSquareOnSquare)
        }
        Button {
            controller.focusBoard(board.id)
            windowModel.showSaveEssentialPanel(for: board)
        } label: {
            Label("Save as Essential…", systemSymbol: .sparkles)
        }
        Button {
            controller.copyBoardID(board.id)
        } label: {
            Label("Copy Board ID", systemSymbol: .documentOnDocument)
        }
        Button {
            controller.focusBoard(board.id)
            windowModel.toggleFocusedBoardMaximized()
        } label: {
            Label(
                windowModel.maximizedBoardID == board.id ? "Restore Board Size" : "Maximize Board",
                systemSymbol: windowModel.maximizedBoardID == board.id
                    ? .arrowDownRightAndArrowUpLeft : .arrowUpLeftAndArrowDownRight)
        }
        Button {
            controller.focusBoard(board.id)
            windowModel.centerFocusedBoard()
        } label: {
            Label("Center Board", systemSymbol: .scope)
        }
        if board.isZmx {
            Button {
                controller.focusBoard(board.id)
                windowModel.showZmxSessions(selectedSessionName: board.zmxSessionName)
            } label: {
                Label {
                    Text("zmx Sessions…")
                } icon: {
                    Image(systemSymbol: .appleTerminalOnRectangle)
                }
            }
        }
        Divider()
        Button {
            controller.focusBoard(board.id)
            controller.adjustFocusedSheetSize(by: 1)
        } label: {
            Label("Increase Font Size", systemSymbol: .plus)
        }
        Button {
            controller.focusBoard(board.id)
            controller.adjustFocusedSheetSize(by: -1)
        } label: {
            Label("Decrease Font Size", systemSymbol: .minus)
        }
        Button {
            controller.focusBoard(board.id)
            controller.resetFocusedSheetSize()
        } label: {
            Label("Reset Font Size", systemSymbol: .arrowCounterclockwise)
        }
        Button {
            controller.focusBoard(board.id)
            controller.captureFocusedSheetScreenshot()
        } label: {
            Label("Capture Current Sheet Screenshot...", systemSymbol: .camera)
        }
        Divider()
        Button {
            controller.focusBoard(board.id)
            controller.moveFocusedBoardLeft()
        } label: {
            Label("Move Board Left", systemSymbol: .arrowLeft)
        }
        .disabled(!controller.canMoveBoard(board.id, by: -1))
        Button {
            controller.focusBoard(board.id)
            controller.moveFocusedBoardRight()
        } label: {
            Label("Move Board Right", systemSymbol: .arrowRight)
        }
        .disabled(!controller.canMoveBoard(board.id, by: 1))
        if controller.state.desks.count > 1 {
            Menu {
                ForEach(Array(controller.state.desks.enumerated()), id: \.element.id) { entry in
                    if entry.element.id != boardDeskID {
                        Button("\(entry.offset + 1). \(entry.element.label)") {
                            controller.focusBoard(board.id)
                            controller.moveFocusedBoard(toDeskNumber: entry.offset + 1)
                        }
                    }
                }
            } label: {
                Label("Move to Desk", systemSymbol: .rectangleStack)
            }
        }
        Divider()
        Button(role: .destructive) {
            controller.removeBoard(board.id)
        } label: {
            Label("Remove Board", systemSymbol: .xmark)
        }
    }

    private var boardDeskID: DeskID? {
        controller.boardIndices(for: board.id).map { controller.state.desks[$0.deskOffset].id }
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
    let onBeforeHide: () -> Void
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
        coordinator.onBeforeHide?()
        coordinator.onSurfaceVisibilityChange?(false)
        coordinator.onSurfaceVisibilityChange = nil
        coordinator.onBeforeHide = nil
    }

    private func update(_ view: AppTerminalView, coordinator: Coordinator) {
        coordinator.onSurfaceVisibilityChange = onSurfaceVisibilityChange
        coordinator.onBeforeHide = onBeforeHide
        if isHidden && !view.isHidden { onBeforeHide() }
        view.isHidden = isHidden
        onSurfaceVisibilityChange(!isHidden)
    }

    final class Coordinator {
        fileprivate var onSurfaceVisibilityChange: ((Bool) -> Void)?
        fileprivate var onBeforeHide: (() -> Void)?
    }
}
