public import AppKit
public import DenDomain
public import DenModels
import SFSafeSymbols
public import SwiftUI

public struct WebBoardView: View {
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(DeskFilterModel.self) private var deskFilter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let board: BoardState
    let isFocused: Bool
    let focusRequest: BoardFocusRequest?
    let isDragging: Bool
    let model: BoardSurfaceModel
    let surface: NSView
    let onSurfaceReady: (NSWindow) -> Bool
    let onBeforeHide: @MainActor () async -> Void
    let faviconURL: URL?
    let isShowingInitialLoadFallback: Bool
    let isLoading: Bool
    let estimatedProgress: Double
    let canGoBack: Bool
    let canGoForward: Bool
    let highlightID: UUID?
    let highlightRect: CGRect?
    let onAppear: () -> Void
    let onActivate: () -> Void
    let onReload: () -> Void
    let onHardReload: () -> Void
    let onPictureInPicture: () -> Void
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

    public init(
        model: BoardSurfaceModel, board: BoardState, isFocused: Bool, focusRequest: BoardFocusRequest?,
        isDragging: Bool, profileColor: Color, width: Double, height: Double, isPointerFocusEnabled: Bool,
        isVisibleInViewport: Bool, onFocus: @escaping () -> Void, onGoToFirst: @escaping () -> Void,
        onGoBack: @escaping () -> Void, onGoForward: @escaping () -> Void, onRemove: @escaping () -> Void,
        onDragChanged: @escaping (DragGesture.Value) -> Void, onDragEnded: @escaping (DragGesture.Value) -> Void,
        surface: NSView, onSurfaceReady: @escaping (NSWindow) -> Bool,
        onBeforeHide: @escaping @MainActor () async -> Void, faviconURL: URL?, isShowingInitialLoadFallback: Bool,
        isLoading: Bool, estimatedProgress: Double, canGoBack: Bool, canGoForward: Bool, highlightID: UUID?,
        highlightRect: CGRect?, onAppear: @escaping () -> Void, onActivate: @escaping () -> Void,
        onReload: @escaping () -> Void, onHardReload: @escaping () -> Void, onPictureInPicture: @escaping () -> Void
    ) {
        self.model = model
        self.board = board
        self.isFocused = isFocused
        self.focusRequest = focusRequest
        self.isDragging = isDragging
        self.profileColor = profileColor
        self.width = width
        self.height = height
        self.isPointerFocusEnabled = isPointerFocusEnabled
        self.isVisibleInViewport = isVisibleInViewport
        self.onFocus = onFocus
        self.onGoToFirst = onGoToFirst
        self.onGoBack = onGoBack
        self.onGoForward = onGoForward
        self.onRemove = onRemove
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.surface = surface
        self.onSurfaceReady = onSurfaceReady
        self.onBeforeHide = onBeforeHide
        self.faviconURL = faviconURL
        self.isShowingInitialLoadFallback = isShowingInitialLoadFallback
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.highlightID = highlightID
        self.highlightRect = highlightRect
        self.onAppear = onAppear
        self.onActivate = onActivate
        self.onReload = onReload
        self.onHardReload = onHardReload
        self.onPictureInPicture = onPictureInPicture
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .top) {
                WebBoardSurface(
                    webView: surface, isHidden: !isSurfaceVisible, focusRequest: focusRequest,
                    onSurfaceReady: onSurfaceReady, onBeforeHide: onBeforeHide
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { _ in
                            guard isPointerFocusEnabled else { return }
                            onFocus()
                        }
                )
                if isShowingInitialLoadFallback {
                    initialLoadFallback
                }

                if isLoading {
                    loadingIndicator
                }

                if let highlightRect, let highlightID {
                    ActionHighlightView(rect: highlightRect, color: profileColor)
                        .id(highlightID)
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
        .onAppear(perform: onAppear)
        .onChange(of: isFocused, initial: true) { _, isFocused in
            guard isFocused else { return }
            onActivate()
        }
    }

    private var isSurfaceVisible: Bool {
        isVisibleInViewport && !windowModel.isOverviewPresented
            && !(windowModel.isDrawerOpen && model.drawerStyle == .bottom)
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
                    width: geometry.size.width * max(0.05, min(estimatedProgress, 1)),
                    height: 2
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .accessibilityElement()
        .accessibilityLabel("Loading Current Sheet")
        .accessibilityValue("\(Int(estimatedProgress * 100)) percent")
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
                    model.perform(.focus)
                    model.perform(.moveLeft)
                },
                onMoveRight: {
                    model.perform(.focus)
                    model.perform(.moveRight)
                },
                leadingContent: {
                    AsyncImage(url: faviconURL) { image in
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
        .background(
            windowModel.isDenMode && isFocused
                ? profileColor.opacity(DenSurfaceColors.focusedBoardHeaderOpacity) : Color.clear
        )
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
            model.perform(.inspect)
        } label: {
            Label("Inspect Current Sheet", systemSymbol: .magnifyingglass)
        }

        Divider()

        Button {
            model.perform(.focus)
            model.perform(.duplicate)
        } label: {
            Label("Duplicate Current Sheet", systemSymbol: .plusSquareOnSquare)
        }
        .onAppear {
            model.perform(.focus)
        }

        Button {
            model.perform(.focus)
            model.perform(.keepInDrawer)
        } label: {
            Label("Keep Current Sheet in Drawer", systemSymbol: .trayAndArrowDown)
        }

        Button {
            model.perform(.focus)
            windowModel.showSaveEssentialPanel(for: board)
        } label: {
            Label("Save as Essential…", systemSymbol: .sparkles)
        }

        Button {
            model.perform(.copyID)
        } label: {
            Label("Copy Board ID", systemSymbol: .documentOnDocument)
        }

        Button {
            model.perform(.copyLocation)
        } label: {
            Label("Copy Current Sheet URL", systemSymbol: .documentOnDocument)
        }
        .disabled(board.currentSheetURL == nil && board.firstSheetURL == nil)

        Button {
            onReload()
        } label: {
            Label("Reload Current Sheet", systemSymbol: .arrowClockwise)
        }

        Button {
            onHardReload()
        } label: {
            Label("Hard Reload Current Sheet", systemSymbol: .arrowClockwiseCircle)
        }

        Button {
            model.perform(.focus)
            model.perform(.goToFirst)
        } label: {
            Label("Return to First Sheet", systemSymbol: .backwardEnd)
        }
        .disabled(!canReturnToFirstSheet)

        if model.sheetNavigationEnabled {
            Button {
                model.perform(.toggleNavigation)
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
            model.perform(.focus)
            model.perform(.screenshot)
        } label: {
            Label("Capture Current Sheet Screenshot...", systemSymbol: .camera)
        }

        Button {
            onPictureInPicture()
        } label: {
            Label("Toggle Picture in Picture", systemSymbol: .pip)
        }

        Divider()

        Button {
            model.perform(.focus)
            model.perform(.increaseSize)
        } label: {
            Label("Increase Sheet Scale", systemSymbol: .plus)
        }

        Button {
            model.perform(.focus)
            model.perform(.decreaseSize)
        } label: {
            Label("Decrease Sheet Scale", systemSymbol: .minus)
        }

        Button {
            model.perform(.focus)
            model.perform(.resetSize)
        } label: {
            Label("Reset Sheet Scale", systemSymbol: .arrowCounterclockwise)
        }

        Divider()

        Button {
            model.perform(.focus)
            windowModel.toggleFocusedBoardMaximized()
        } label: {
            Label(maximizationLabel, systemSymbol: maximizationSystemSymbol)
        }

        Button {
            model.perform(.focus)
            windowModel.centerFocusedBoard()
        } label: {
            Label("Center Board", systemSymbol: .scope)
        }

        Divider()

        Button {
            model.perform(.focus)
            model.perform(.moveLeft)
        } label: {
            Label("Move Board Left", systemSymbol: .arrowLeft)
        }
        .disabled(!model.canMoveLeft)

        Button {
            model.perform(.focus)
            model.perform(.moveRight)
        } label: {
            Label("Move Board Right", systemSymbol: .arrowRight)
        }
        .disabled(!model.canMoveRight)

        if model.desks.count > 1 {
            Menu {
                ForEach(Array(model.desks.enumerated()), id: \.element.id) { entry in
                    if entry.element.id != boardDeskID {
                        Button("\(entry.offset + 1). \(entry.element.label)") {
                            model.perform(.focus)
                            model.perform(.moveToDesk(entry.offset + 1))
                        }
                    }
                }
            } label: {
                Label("Move to Desk", systemSymbol: .rectangleStack)
            }
        }

        Divider()

        Button(role: .destructive) {
            model.perform(.remove)
        } label: {
            Label("Remove Board", systemSymbol: .xmark)
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            if let label = model.inputSourceLabel {
                BoardInputSourceBadge(label: label, isFocused: isFocused)
            }

            if model.sheetNavigationEnabled {
                Button {
                    model.perform(.toggleNavigation)
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
                    canGoBack
                        ? Color.primary
                        : Color.secondary.opacity(0.35)
                )
                .disabled(!canGoBack)
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
                    canGoForward
                        ? Color.primary
                        : Color.secondary.opacity(0.35)
                )
                .disabled(!canGoForward)
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

    private var boardDeskID: DeskID? { model.boardDeskID }

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
            preference: model.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}

private struct ActionHighlightView: View {
    let rect: CGRect
    let color: Color
    @State private var opacity: Double = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
            .stroke(color, lineWidth: 3)
            .background(RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous).fill(color.opacity(0.15)))
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
