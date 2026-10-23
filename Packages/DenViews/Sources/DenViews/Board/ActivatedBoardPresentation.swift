public import DenDomain
public import DenModels
public import SwiftUI

public struct ActivatedBoardPresentation {
    public let board: BoardState
    public let isFocused: Bool
    public let focusRequest: BoardFocusRequest?
    public let isDragging: Bool
    public let isPointerFocusEnabled: Bool
    public let profileColor: Color
    public let size: CGSize
    public let isVisible: Bool
    public let onFocus: () -> Void
    public let onDragChanged: (DragGesture.Value) -> Void
    public let onDragEnded: (DragGesture.Value) -> Void
}
