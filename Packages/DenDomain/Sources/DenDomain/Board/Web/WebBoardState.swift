import Foundation

public struct WebBoardState: Equatable {
    public var currentSheetURL: URL?
    public var firstSheetURL: URL?
    public var sheetNavigationPaused: Bool
    public var denAPIEnabled: Bool
    public var backgroundExecutionEnabled: Bool

    public init(
        currentSheetURL: URL? = nil,
        firstSheetURL: URL? = nil,
        sheetNavigationPaused: Bool = false,
        denAPIEnabled: Bool = false,
        backgroundExecutionEnabled: Bool = false
    ) {
        self.currentSheetURL = currentSheetURL.map(WebURLPolicy.canonicalSheetURL)
        self.firstSheetURL = firstSheetURL.map(WebURLPolicy.canonicalSheetURL)
        self.sheetNavigationPaused = sheetNavigationPaused
        self.denAPIEnabled = denAPIEnabled
        self.backgroundExecutionEnabled = backgroundExecutionEnabled
    }
}
