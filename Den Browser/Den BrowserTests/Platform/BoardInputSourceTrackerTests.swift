import AppKit
import DenDomain
import Testing

@testable import Den_Browser

@MainActor
struct BoardInputSourceTrackerTests {
    @Test func tracksAndStoresInputSourceForBoards() {
        // Arrange
        let tracker = BoardInputSourceTracker()
        let boardA = BoardID()
        let boardB = BoardID()

        // Act
        tracker.setLastInputSource("com.apple.keylayout.ABC", for: boardA)
        tracker.setLastInputSource("com.google.inputmethod.Japanese.base", for: boardB)

        // Assert
        #expect(tracker.lastInputSource(for: boardA) == "com.apple.keylayout.ABC")
        #expect(tracker.lastInputSource(for: boardB) == "com.google.inputmethod.Japanese.base")
    }

    @Test func boardWillRemoveClearsStoredSource() {
        // Arrange
        let tracker = BoardInputSourceTracker()
        let board = BoardID()
        tracker.setLastInputSource("com.apple.keylayout.ABC", for: board)
        #expect(tracker.lastInputSource(for: board) == "com.apple.keylayout.ABC")

        // Act
        tracker.boardWillRemove(board)

        // Assert
        #expect(tracker.lastInputSource(for: board) == nil)
    }

    @Test func boardDidFocusUpdatesCurrentBoardID() {
        // Arrange
        let tracker = BoardInputSourceTracker()
        let board = BoardID()

        // Act
        tracker.boardDidFocus(board, isEnabled: false)

        // Assert
        #expect(tracker.currentBoardID == board)
    }

    @Test func shortLabelResolvesExpectedSymbols() {
        // Act & Assert
        #expect(BoardInputSourceTracker.resolveShortLabel(for: "com.apple.keylayout.ABC") == "A")
        #expect(BoardInputSourceTracker.resolveShortLabel(for: "com.google.inputmethod.Japanese.Roman") == "A")
        #expect(BoardInputSourceTracker.resolveShortLabel(for: "com.google.inputmethod.Japanese.base") == "あ")
        #expect(BoardInputSourceTracker.resolveShortLabel(for: "com.apple.inputmethod.Kotoeri.Japanese") == "あ")
        #expect(BoardInputSourceTracker.resolveShortLabel(for: "com.apple.keylayout.US") == "A")
    }

    @Test func canRecordInputSourceSuppressesRecording() {
        // Arrange
        let tracker = BoardInputSourceTracker()
        let board = BoardID()
        tracker.setLastInputSource("com.apple.keylayout.ABC", for: board)
        tracker.boardDidFocus(board, isEnabled: false)
        tracker.canRecordInputSource = { false }

        // Act
        NotificationCenter.default.post(
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )

        // Assert
        #expect(tracker.lastInputSource(for: board) == "com.apple.keylayout.ABC")
    }

    @Test func disabledFeatureSuppressesRecording() {
        // Arrange
        let tracker = BoardInputSourceTracker()
        let board = BoardID()
        tracker.setLastInputSource("com.apple.keylayout.ABC", for: board)
        tracker.boardDidFocus(board, isEnabled: false)
        tracker.isEnabled = { false }

        // Act
        NotificationCenter.default.post(
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )

        // Assert
        #expect(tracker.lastInputSource(for: board) == "com.apple.keylayout.ABC")
    }
}
