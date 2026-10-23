import DenApplication
import DenDomain
import DenModels
import DenViews
import SwiftUI

struct InspectionBoardView: View {
    @Environment(ProfileWindowSession.self) private var session
    let board: BoardState
    let isFocused: Bool
    let focusRequest: BoardFocusRequest?
    let isDragging: Bool
    let isPointerFocusEnabled: Bool
    let profileColor: Color
    let width: Double
    let height: Double
    let isVisibleInViewport: Bool
    let targetBoardID: BoardID
    let onFocus: () -> Void
    let onRemove: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    var body: some View {
        if let runtime = session.resources.webRuntimes[targetBoardID] {
            ObservedInspectionBoard(
                runtime: runtime, content: { generation in display(generation: generation, runtime: runtime) }
            )
            .id(runtime.id)
        } else {
            display(generation: 0, runtime: nil)
        }
    }

    private func display(generation: Int, runtime: WebRuntime?) -> some View {
        DenViews.InspectionBoardView(
            model: InspectionBoardModel(session: session, targetBoardID: targetBoardID, runtime: runtime),
            surfaceModel: BoardSurfaceModel(board: board, session: session), runtimeGeneration: generation,
            focusTarget: { session.boardNavigation.focusBoard(targetBoardID, exitsDenMode: true) },
            board: board,
            isFocused: isFocused,
            focusRequest: focusRequest,
            isDragging: isDragging,
            isPointerFocusEnabled: isPointerFocusEnabled,
            profileColor: profileColor,
            width: width,
            height: height,
            isVisibleInViewport: isVisibleInViewport,
            targetBoardID: targetBoardID,
            onFocus: onFocus,
            onRemove: onRemove,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded)
    }
}

private struct ObservedInspectionBoard<Content: View>: View {
    @ObservedObject var runtime: WebRuntime
    let content: (Int) -> Content
    var body: some View { content(runtime.inspectionPageGeneration) }
}

extension InspectionBoardModel {
    convenience init(session: ProfileWindowSession, targetBoardID: BoardID, runtime: WebRuntime?) {
        self.init(
            runtimeID: runtime?.id,
            targetBoard: { [weak session] in session?.resources.state.board(for: targetBoardID) },
            pageGeneration: { [weak runtime] in runtime?.inspectionPageGeneration ?? 0 },
            hasPage: { [weak runtime] in runtime?.webView.url != nil },
            isActive: { [weak runtime] in runtime?.isInspectionActive ?? false },
            startCollection: { [weak runtime] in runtime?.startInspectionCollection(highlightColor: $0) },
            setHighlightColor: { [weak runtime] in runtime?.setInspectionHighlightColor($0) },
            beginPicking: { [weak runtime] in runtime?.beginInspectionPicking(highlightColor: $0) },
            selectNode: { [weak runtime] in runtime?.selectInspectionNode($0) },
            highlightNode: { [weak runtime] in runtime?.highlightInspectionNode($0) },
            readSnapshot: { [weak runtime] in await runtime?.readInspectionSnapshot() ?? .empty },
            readChildren: { [weak runtime] in await runtime?.readInspectionChildren(for: $0) ?? [] },
            refreshChildren: { [weak runtime] in await runtime?.readInspectionChildren(for: $0) ?? [:] })
    }
}
