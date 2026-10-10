import DenDesign
import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

struct WebBoardView: View {
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
    @ObservedObject var runtime: WebRuntime
    let profileColor: Color
    let width: Double
    let height: Double
    let isPointerFocusEnabled: Bool
    var isVisibleInViewport: Bool = true
    let onFocus: () -> Void
    let onGoToFirst: () -> Void
    let onGoBack: () -> Void
    let onGoForward: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                WebBoardSurface(
                    webView: runtime.webView,
                    isHidden: !isVisibleInViewport || windowModel.isOverviewPresented
                        || (windowModel.isDrawerOpen && preferences.drawerStyle == .bottom),
                    focusRequest: focusRequest,
                    onSurfaceReady: { window in
                        guard runtime.webView.fullscreenState == .notInFullscreen else {
                            return true
                        }
                        guard
                            needsFirstResponderActivation(
                                window.firstResponder,
                                target: runtime.webView
                            )
                        else { return true }
                        return window.makeFirstResponder(runtime.webView)
                    }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { _ in
                            guard isPointerFocusEnabled else { return }
                            onFocus()
                        }
                )
                if runtime.isShowingInitialLoadFallback {
                    initialLoadFallback
                }

                if runtime.isLoading {
                    loadingIndicator
                }

                if let highlight = runtime.actionHighlight {
                    ActionHighlightView(rect: highlight.rect, color: profileColor)
                        .id(highlight.id)
                }
            }
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
        .onAppear {
            controller.sheetNavigation.refreshConfiguration(for: runtime.webView)
        }
        .onChange(of: isFocused, initial: true) { _, isFocused in
            guard isFocused else { return }
            runtime.activateWebExtensionTab()
        }
    }

    private var initialLoadFallback: some View {
        DenSurfaceColors.standardBackgroundColor
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var loadingIndicator: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(profileColor)
                .frame(
                    width: geometry.size.width * max(0.05, min(runtime.estimatedProgress, 1)),
                    height: 2
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .accessibilityElement()
        .accessibilityLabel("Loading Current Sheet")
        .accessibilityValue("\(Int(runtime.estimatedProgress * 100)) percent")
    }

    private var isFocusModeDeemphasized: Bool {
        windowModel.isFocusModePresented && !isFocused && !deskFilter.isPresented
    }

    private var isFocusModeFocused: Bool {
        windowModel.isFocusModePresented && isFocused
    }

    private var header: some View {
        headerContent
            .contextMenu {
                if isContextMenuEnabled {
                    boardContextMenu
                }
            }
    }

    private var headerContent: some View {
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
                    AsyncImage(url: runtime.faviconURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemSymbol: .globe)
                            .foregroundStyle(.secondary)
                    }
                }
            )

            navigationButtons
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
    }

    @ViewBuilder
    private var boardContextMenu: some View {
        Button {
            controller.createInspectionBoard(targetBoardID: board.id)
        } label: {
            Label("Inspect Current Sheet", systemSymbol: .magnifyingglass)
        }

        Divider()

        Button {
            controller.focusBoard(board.id)
            controller.duplicateFocusedBoard()
        } label: {
            Label("Duplicate Current Sheet", systemSymbol: .plusSquareOnSquare)
        }
        .onAppear {
            controller.focusBoard(board.id)
        }

        Button {
            controller.focusBoard(board.id)
            controller.keepFocusedSheetInDrawer()
        } label: {
            Label("Keep Current Sheet in Drawer", systemSymbol: .trayAndArrowDown)
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
            controller.copyBoardLocation(board.id)
        } label: {
            Label("Copy Current Sheet URL", systemSymbol: .documentOnDocument)
        }
        .disabled(board.currentSheetURL == nil && board.firstSheetURL == nil)

        Button {
            runtime.webView.reload()
        } label: {
            Label("Reload Current Sheet", systemSymbol: .arrowClockwise)
        }

        Button {
            runtime.webView.reloadFromOrigin()
        } label: {
            Label("Hard Reload Current Sheet", systemSymbol: .arrowClockwiseCircle)
        }

        Button {
            controller.focusBoard(board.id)
            controller.goToFirstSheetInFocusedBoard()
        } label: {
            Label("Return to First Sheet", systemSymbol: .backwardEnd)
        }
        .disabled(!canReturnToFirstSheet)

        if controller.sheetNavigation.isEnabled {
            Button {
                controller.toggleBoardSheetNavigationPause(board.id)
            } label: {
                Label(
                    board.sheetNavigationPaused
                        ? "Resume Sheet Navigation for this Board"
                        : "Pause Sheet Navigation for this Board",
                    systemSymbol: board.sheetNavigationPaused ? .playCircle : .pauseCircle
                )
            }
        }

        Button {
            controller.focusBoard(board.id)
            controller.captureFocusedSheetScreenshot()
        } label: {
            Label("Capture Current Sheet Screenshot...", systemSymbol: .camera)
        }

        Button {
            runtime.togglePictureInPicture()
        } label: {
            Label("Toggle Picture in Picture", systemSymbol: .pip)
        }

        Divider()

        Button {
            controller.focusBoard(board.id)
            controller.adjustFocusedSheetSize(by: 1)
        } label: {
            Label("Increase Sheet Scale", systemSymbol: .plus)
        }

        Button {
            controller.focusBoard(board.id)
            controller.adjustFocusedSheetSize(by: -1)
        } label: {
            Label("Decrease Sheet Scale", systemSymbol: .minus)
        }

        Button {
            controller.focusBoard(board.id)
            controller.resetFocusedSheetSize()
        } label: {
            Label("Reset Sheet Scale", systemSymbol: .arrowCounterclockwise)
        }

        Divider()

        Button {
            controller.focusBoard(board.id)
            windowModel.toggleFocusedBoardMaximized()
        } label: {
            Label(maximizationLabel, systemSymbol: maximizationSystemSymbol)
        }

        Button {
            controller.focusBoard(board.id)
            windowModel.centerFocusedBoard()
        } label: {
            Label("Center Board", systemSymbol: .scope)
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

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            if controller.sheetNavigation.isEnabled {
                Button {
                    controller.toggleBoardSheetNavigationPause(board.id)
                } label: {
                    Image(
                        systemSymbol: board.sheetNavigationPaused ? .pauseCircleFill : .keyboard
                    )
                    .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .help(
                    board.sheetNavigationPaused
                        ? "Resume Sheet Navigation for this Board" : "Pause Sheet Navigation for this Board"
                )
                .accessibilityLabel(
                    board.sheetNavigationPaused
                        ? "Resume Sheet Navigation for this Board" : "Pause Sheet Navigation for this Board")
            }

            withBoardContextMenu(
                Button(action: onGoToFirst) {
                    Image(systemSymbol: .backwardEnd)
                        .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(
                    canReturnToFirstSheet
                        ? Color.primary
                        : Color.secondary.opacity(0.35)
                )
                .disabled(!canReturnToFirstSheet)
                .help("Return to First Sheet")
                .accessibilityLabel("Return to First Sheet")
            )

            withBoardContextMenu(
                Button(action: onGoBack) {
                    Image(systemSymbol: .chevronLeft)
                        .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(
                    runtime.webView.canGoBack
                        ? Color.primary
                        : Color.secondary.opacity(0.35)
                )
                .disabled(!runtime.webView.canGoBack)
                .help("Back in sheet stack")
                .accessibilityLabel("Back in sheet stack")
            )

            withBoardContextMenu(
                Button(action: onGoForward) {
                    Image(systemSymbol: .chevronRight)
                        .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(
                    runtime.webView.canGoForward
                        ? Color.primary
                        : Color.secondary.opacity(0.35)
                )
                .disabled(!runtime.webView.canGoForward)
                .help("Forward in sheet stack")
                .accessibilityLabel("Forward in sheet stack")
            )

            withBoardContextMenu(
                Button(action: onRemove) {
                    Image(systemSymbol: .xmark)
                        .frame(width: DenLayout.boardControlSize, height: DenLayout.boardControlSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .padding(.leading, 4)
                .help("Remove Board")
                .accessibilityLabel("Remove Board")
            )
        }
    }

    private func withBoardContextMenu<Content: View>(_ content: Content) -> some View {
        content.contextMenu {
            if isContextMenuEnabled {
                boardContextMenu
            }
        }
    }

    private var canReturnToFirstSheet: Bool {
        guard
            let firstSheetURL = board.firstSheetURL,
            let currentSheetURL = board.currentSheetURL
        else { return false }
        return currentSheetURL != firstSheetURL
    }

    private var isContextMenuEnabled: Bool {
        isPointerFocusEnabled && !windowModel.isBoardDragging
    }

    private var boardDeskID: DeskID? {
        controller.boardIndices(for: board.id).map { controller.state.desks[$0.deskOffset].id }
    }

    private var maximizationLabel: String {
        windowModel.maximizedBoardID == board.id ? "Restore Board Size" : "Maximize Board"
    }

    private var maximizationSystemSymbol: SFSymbol {
        windowModel.maximizedBoardID == board.id
            ? .arrowDownRightAndArrowUpLeft
            : .arrowUpLeftAndArrowDownRight
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}

private struct ActionHighlightView: View {
    let rect: CGRect
    let color: Color
    @State private var opacity: Double = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(color, lineWidth: 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.15)))
            .shadow(color: color.opacity(0.6), radius: 8)
            .frame(width: max(0, rect.width + 4), height: max(0, rect.height + 4))
            .position(x: rect.midX, y: rect.midY)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    opacity = 0
                }
            }
    }
}
