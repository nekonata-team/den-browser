import DenApplication
import DenDomain
import DenPresentationModels
import DenViews
import SwiftUI

struct WebBoardView: View {
    @Environment(ProfileWindowSession.self) private var session
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
        DenViews.WebBoardView(
            model: BoardSurfaceModel(board: board, session: session),
            board: board,
            isFocused: isFocused,
            focusRequest: focusRequest,
            isDragging: isDragging,
            profileColor: profileColor,
            width: width,
            height: height,
            isPointerFocusEnabled: isPointerFocusEnabled,
            isVisibleInViewport: isVisibleInViewport,
            onFocus: onFocus,
            onGoToFirst: onGoToFirst,
            onGoBack: onGoBack,
            onGoForward: onGoForward,
            onRemove: onRemove,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded,
            surface: runtime.webView,
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
            },
            onBeforeHide: {
                guard session.resources.data.snapshot.activeDrag == nil else { return }
                guard session.resources.webRuntimes[board.id] === runtime else { return }
                await session.resources.facingCapture.captureWeb(
                    boardID: board.id, webView: runtime.webView)
            },
            faviconURL: runtime.faviconURL,
            isShowingInitialLoadFallback: runtime.isShowingInitialLoadFallback,
            isLoading: runtime.isLoading,
            estimatedProgress: runtime.estimatedProgress,
            canGoBack: runtime.webView.canGoBack,
            canGoForward: runtime.webView.canGoForward,
            highlightID: runtime.actionHighlight?.id,
            highlightRect: runtime.actionHighlight?.rect,
            onAppear: {
                guard session.connection.runtimes === session.runtimes,
                    session.resources.webRuntimes[board.id] === runtime
                else { return }
                _ = session.runtimes.webRuntime(for: board)
                session.configuration.sheetNavigation.refreshConfiguration(for: runtime.webView)
            },
            onActivate: { runtime.activateWebExtensionTab() },
            onReload: { runtime.webView.reload() },
            onHardReload: { runtime.webView.reloadFromOrigin() },
            onPictureInPicture: { runtime.togglePictureInPicture() }
        )
    }
}
