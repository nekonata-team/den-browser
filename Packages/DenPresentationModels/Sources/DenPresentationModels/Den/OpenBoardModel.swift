import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class OpenBoardModel {
    @ObservationIgnored private let openBoard: (String, Double?, BoardID?) -> String?

    public var initialURL: URL?
    public var input = "" {
        didSet {
            let stripped = WebURLPolicy.stripNewlines(input)
            if input != stripped {
                input = stripped
            }
        }
    }
    public var afterBoardID: BoardID?
    public var message: String?

    public init(openBoard: @escaping (String, Double?, BoardID?) -> String?) {
        self.openBoard = openBoard
    }

    public func preparePresentation(initialURL: URL? = nil, afterBoardID: BoardID? = nil) {
        self.initialURL = initialURL
        self.afterBoardID = afterBoardID
        if let initialURL { input = initialURL.absoluteString }
        message = nil
    }

    public func endPresentation(preservingDraft: Bool) {
        initialURL = nil
        guard !preservingDraft else { return }
        afterBoardID = nil
        message = nil
    }

    public func clearDraft() {
        input = ""
        afterBoardID = nil
    }

    public func resetPresentation() {
        initialURL = nil
        input = ""
        afterBoardID = nil
        message = nil
    }

    public func invalidateBoard(_ boardID: BoardID) {
        if afterBoardID == boardID { afterBoardID = nil }
    }

    public func submit(
        _ input: String? = nil,
        preferredWidth: Double? = nil
    ) {
        message = nil
        message = openBoard(input ?? self.input, preferredWidth, afterBoardID)
    }
}
