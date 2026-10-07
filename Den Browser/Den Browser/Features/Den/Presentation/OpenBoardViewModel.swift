import DenDomain
import Foundation
import Observation

@MainActor
@Observable
final class OpenBoardViewModel {
    let store: DenStore

    var initialURL: URL?
    var input = "" {
        didSet {
            let stripped = WebURLPolicy.stripNewlines(input)
            if input != stripped {
                input = stripped
            }
        }
    }
    var afterBoardID: BoardID?
    var message: String?

    init(store: DenStore) {
        self.store = store
    }

    func preparePresentation(initialURL: URL? = nil, afterBoardID: BoardID? = nil) {
        self.initialURL = initialURL
        self.afterBoardID = afterBoardID
        if let initialURL { input = initialURL.absoluteString }
        message = nil
    }

    func endPresentation(preservingDraft: Bool) {
        initialURL = nil
        guard !preservingDraft else { return }
        afterBoardID = nil
        message = nil
    }

    func clearDraft() {
        input = ""
        afterBoardID = nil
    }

    func resetPresentation() {
        initialURL = nil
        input = ""
        afterBoardID = nil
        message = nil
    }

    func invalidateBoard(_ boardID: BoardID) {
        if afterBoardID == boardID { afterBoardID = nil }
    }

    func submit(
        _ input: String? = nil,
        preferredWidth: Double? = nil,
        zmxRootSessionName: String? = nil
    ) {
        message = nil
        _ = store.openBoard(
            input: input ?? self.input,
            preferredWidth: preferredWidth,
            afterBoardID: afterBoardID,
            opensFromOpenBoardPanel: true,
            zmxRootSessionName: zmxRootSessionName)
    }
}
