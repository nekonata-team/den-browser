import SFSafeSymbols
import SwiftUI

struct BoardView: View {
    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let board: BoardState
    let isFocused: Bool
    let focusRequest: BoardFocusRequest?
    let isDragging: Bool
    @ObservedObject var runtime: BoardRuntime
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
                BoardWebView(
                    webView: runtime.webView,
                    isHidden: !isVisibleInViewport || store.isOverviewPresented,
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
            store.sheetNavigation.refreshConfiguration(for: runtime.webView)
        }
        .onChange(of: isFocused, initial: true) { _, isFocused in
            guard isFocused else { return }
            runtime.activateWebExtensionTab()
        }
    }

    private var initialLoadFallback: some View {
        DenSurfaceColors.webViewFallbackBackground.color
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
        store.isFocusModePresented && !isFocused && !store.isDeskFilterPresented
    }

    private var isFocusModeFocused: Bool {
        store.isFocusModePresented && isFocused
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
                    store.focusBoard(board.id)
                    store.moveFocusedBoardLeft()
                },
                onMoveRight: {
                    store.focusBoard(board.id)
                    store.moveFocusedBoardRight()
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
        .background(store.isDenMode && isFocused ? profileColor.opacity(0.12) : Color.clear)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var boardContextMenu: some View {
        Button {
            store.focusBoard(board.id)
            store.duplicateFocusedBoard()
        } label: {
            Label("Duplicate Current Sheet", systemSymbol: .plusSquareOnSquare)
        }
        .onAppear {
            store.focusBoard(board.id)
        }

        Button {
            store.focusBoard(board.id)
            store.keepFocusedSheetInDrawer()
        } label: {
            Label("Keep Current Sheet in Drawer", systemSymbol: .trayAndArrowDown)
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
            store.focusBoard(board.id)
            store.goToFirstSheetInFocusedBoard()
        } label: {
            Label("Return to First Sheet", systemSymbol: .backwardEnd)
        }
        .disabled(!canReturnToFirstSheet)

        if store.sheetNavigation.isEnabled {
            Button {
                store.toggleBoardSheetNavigationPause(board.id)
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
            store.focusBoard(board.id)
            store.captureFocusedSheetScreenshot()
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
            store.focusBoard(board.id)
            store.adjustFocusedBoardContentSize(by: 1)
        } label: {
            Label("Increase Sheet Scale", systemSymbol: .plus)
        }

        Button {
            store.focusBoard(board.id)
            store.adjustFocusedBoardContentSize(by: -1)
        } label: {
            Label("Decrease Sheet Scale", systemSymbol: .minus)
        }

        Button {
            store.focusBoard(board.id)
            store.resetFocusedBoardContentSize()
        } label: {
            Label("Reset Sheet Scale", systemSymbol: .arrowCounterclockwise)
        }

        Divider()

        Button {
            store.focusBoard(board.id)
            store.toggleFocusedBoardMaximized()
        } label: {
            Label(maximizationLabel, systemSymbol: maximizationSystemSymbol)
        }

        Button {
            store.focusBoard(board.id)
            store.centerFocusedBoard()
        } label: {
            Label("Center Board", systemSymbol: .scope)
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

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            if store.sheetNavigation.isEnabled {
                Button {
                    store.toggleBoardSheetNavigationPause(board.id)
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
        isPointerFocusEnabled && !store.isBoardDragging
    }

    private var boardDeskID: UUID? {
        store.boardIndices(for: board.id).map { store.state.desks[$0.desk].id }
    }

    private var maximizationLabel: String {
        store.maximizedBoardID == board.id ? "Restore Board Size" : "Maximize Board"
    }

    private var maximizationSystemSymbol: SFSymbol {
        store.maximizedBoardID == board.id
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

struct BoardHeaderTitle: View {
    let board: BoardState
    let isFocused: Bool
    var isAnchor: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(board.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if isAnchor {
                    Image(systemSymbol: .pinFill)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Anchor Board")
                }
            }

            if let supplementaryText {
                Text(supplementaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(supplementaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var supplementaryText: String? {
        if let currentSheetURL = board.currentSheetURL {
            return currentSheetURL.absoluteString
        }
        return board.zellijSessionName ?? board.zmxSessionName
    }

    private var accessibilityLabel: String {
        [
            isAnchor ? "Anchor board" : nil,
            "Board: \(board.displayName)",
            supplementaryText,
            isFocused ? "Focused board" : "Board",
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

enum BoardStripCoordinateSpace {
    static let name = "board-strip"
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
