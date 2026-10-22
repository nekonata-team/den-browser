import DenDomain
public import DenPresentationModels
public import SwiftUI

/// M0's pure View / Model boundary probe.
public struct BoardOrderProbeView: View {
    private let model: BoardOrderProbeModel

    public init(model: BoardOrderProbeModel) {
        self.model = model
    }

    public var body: some View {
        ForEach(model.boards) { board in
            Button(board.displayName) {
                model.reorder(board.id, to: BoardIndex(rawValue: 0))
            }
        }
    }
}
