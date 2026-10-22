public import AppKit
public import DenDomain
public import DenPresentationModels
import SFSafeSymbols
public import SwiftUI

public struct TerminalBoardView: View {
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
    let onBeforeHide: () -> Void
    let onSurfaceVisibilityChange: (Bool) -> Void
    let onAdjustFontSize: (Int) -> Int
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

    public init(
        model: BoardSurfaceModel, board: BoardState, isFocused: Bool, focusRequest: BoardFocusRequest?,
        isDragging: Bool, profileColor: Color, width: Double, height: Double, isPointerFocusEnabled: Bool,
        isVisibleInViewport: Bool, onFocus: @escaping () -> Void, onRemove: @escaping () -> Void,
        onDragChanged: @escaping (DragGesture.Value) -> Void, onDragEnded: @escaping (DragGesture.Value) -> Void,
        surface: NSView, onSurfaceReady: @escaping (NSWindow) -> Bool, onBeforeHide: @escaping () -> Void,
        onSurfaceVisibilityChange: @escaping (Bool) -> Void, onAdjustFontSize: @escaping (Int) -> Int
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
        self.onRemove = onRemove
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.surface = surface
        self.onSurfaceReady = onSurfaceReady
        self.onBeforeHide = onBeforeHide
        self.onSurfaceVisibilityChange = onSurfaceVisibilityChange
        self.onAdjustFontSize = onAdjustFontSize
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            TerminalBoardSurface(
                terminalView: surface, onSurfaceVisibilityChange: onSurfaceVisibilityChange, onBeforeHide: onBeforeHide,
                isHidden: !isSurfaceVisible, focusRequest: focusRequest, onSurfaceReady: onSurfaceReady
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
                        appliedFontSizeSteps += onAdjustFontSize(delta)
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
            && !(windowModel.isDrawerOpen && model.drawerStyle == .bottom)
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
                    model.perform(.focus)
                    model.perform(.moveLeft)
                },
                onMoveRight: {
                    model.perform(.focus)
                    model.perform(.moveRight)
                },
                leadingContent: {
                    Image(systemSymbol: boardSymbol(for: board.kind))
                        .foregroundStyle(.secondary)
                }
            )
            HStack(spacing: 2) {
                if let label = model.inputSourceLabel {
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
        .contextMenu { boardContextMenu }
    }

    @ViewBuilder
    private var boardContextMenu: some View {
        Button {
            model.perform(.focus)
            model.perform(.duplicate)
        } label: {
            Label(
                board.isZellij
                    ? "Duplicate Zellij Board"
                    : (board.isZmx ? "Duplicate zmx Board…" : "Duplicate Terminal Board"),
                systemSymbol: .plusSquareOnSquare)
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
            model.perform(.focus)
            windowModel.toggleFocusedBoardMaximized()
        } label: {
            Label(
                windowModel.maximizedBoardID == board.id ? "Restore Board Size" : "Maximize Board",
                systemSymbol: windowModel.maximizedBoardID == board.id
                    ? .arrowDownRightAndArrowUpLeft : .arrowUpLeftAndArrowDownRight)
        }
        Button {
            model.perform(.focus)
            windowModel.centerFocusedBoard()
        } label: {
            Label("Center Board", systemSymbol: .scope)
        }
        if board.isZmx {
            Button {
                model.perform(.focus)
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
            model.perform(.focus)
            model.perform(.increaseSize)
        } label: {
            Label("Increase Font Size", systemSymbol: .plus)
        }
        Button {
            model.perform(.focus)
            model.perform(.decreaseSize)
        } label: {
            Label("Decrease Font Size", systemSymbol: .minus)
        }
        Button {
            model.perform(.focus)
            model.perform(.resetSize)
        } label: {
            Label("Reset Font Size", systemSymbol: .arrowCounterclockwise)
        }
        Button {
            model.perform(.focus)
            model.perform(.screenshot)
        } label: {
            Label("Capture Current Sheet Screenshot...", systemSymbol: .camera)
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

    private var boardDeskID: DeskID? { model.boardDeskID }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: model.motionPreference,
            systemReduceMotion: systemReduceMotion)
    }
}
