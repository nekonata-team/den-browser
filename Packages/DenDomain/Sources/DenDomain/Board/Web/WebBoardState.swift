import Foundation

public struct WebBoardState: Equatable {
    public var currentSheetURL: URL?
    public var firstSheetURL: URL?
    public var sheetNavigationPaused: Bool

    public init(
        currentSheetURL: URL? = nil,
        firstSheetURL: URL? = nil,
        sheetNavigationPaused: Bool = false
    ) {
        self.currentSheetURL = currentSheetURL.map(WebURLPolicy.canonicalSheetURL)
        self.firstSheetURL = firstSheetURL.map(WebURLPolicy.canonicalSheetURL)
        self.sheetNavigationPaused = sheetNavigationPaused
    }
}
