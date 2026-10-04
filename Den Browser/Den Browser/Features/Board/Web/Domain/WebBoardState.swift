import Foundation

struct WebBoardState: Equatable {
    var currentSheetURL: URL?
    var firstSheetURL: URL?
    var sheetNavigationPaused: Bool

    init(
        currentSheetURL: URL? = nil,
        firstSheetURL: URL? = nil,
        sheetNavigationPaused: Bool = false
    ) {
        self.currentSheetURL = currentSheetURL.map(WebURLPolicy.canonicalSheetURL)
        self.firstSheetURL = firstSheetURL.map(WebURLPolicy.canonicalSheetURL)
        self.sheetNavigationPaused = sheetNavigationPaused
    }
}
