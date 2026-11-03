import AppKit
import DenDomain
import Testing

@testable import Den_Browser

@MainActor
struct BoardInputSourceTrackerTests {
    @MainActor
    private final class InputSource {
        let notifications = NotificationCenter()
        var current = "english"
        var selected: [String] = []

        func tracker() -> BoardInputSourceTracker {
            let tracker = BoardInputSourceTracker(notificationCenter: notifications)
            tracker.isEnabled = { true }
            tracker.canRestoreInputSource = { true }
            tracker.canRecordInputSource = { true }
            tracker.readInputSource = { self.current }
            tracker.restoreInputSource = {
                self.current = $0
                self.selected.append($0)
            }
            return tracker
        }
    }

    @Test(.timeLimit(.minutes(1))) func keyboardNavigationRestoresOnlyTheLastBoard() async {
        // Arrange
        let source = InputSource()
        let tracker = source.tracker()
        let restored = AsyncStream<String>.makeStream()
        tracker.restoreInputSource = {
            source.current = $0
            source.selected.append($0)
            restored.continuation.yield($0)
            restored.continuation.finish()
        }
        let first = BoardID()
        let middle = BoardID()
        let last = BoardID()
        tracker.boardDidFocus(first, isEnabled: true)
        tracker.setLastInputSource("japanese", for: middle)
        tracker.setLastInputSource("korean", for: last)
        tracker.isHandlingKeyboardAction = true

        // Act
        tracker.boardDidFocus(middle, isEnabled: true)
        tracker.boardDidFocus(last, isEnabled: true)
        tracker.isHandlingKeyboardAction = false

        // Assert
        #expect(source.selected.isEmpty)
        #expect(tracker.lastInputSource(for: middle) == "japanese")
        var iterator = restored.stream.makeAsyncIterator()
        #expect(await iterator.next() == "korean")
        #expect(source.selected == ["korean"])
    }

    @Test func reselectingFocusedBoardRestoresSourceAfterNativeEditing() {
        // Arrange
        let source = InputSource()
        source.current = "japanese"
        let tracker = source.tracker()
        let board = BoardID()
        tracker.boardDidFocus(board, isEnabled: true)
        tracker.canRecordInputSource = { false }
        source.current = "english"
        source.notifications.post(name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)

        // Act
        tracker.canRecordInputSource = { true }
        tracker.boardDidFocus(board, isEnabled: true)

        // Assert
        #expect(source.current == "japanese")
        #expect(source.selected == ["japanese"])
        #expect(tracker.lastInputSource(for: board) == "japanese")
    }

    @Test func reselectingBoardWhileRestorationIsPendingPreservesSavedSource() {
        // Arrange
        let source = InputSource()
        let tracker = source.tracker()
        let board = BoardID()
        tracker.setLastInputSource("japanese", for: board)
        tracker.isHandlingKeyboardAction = true
        tracker.boardDidFocus(board, isEnabled: true)

        // Act
        tracker.boardDidFocus(board, isEnabled: true)

        // Assert
        #expect(source.selected.isEmpty)
        #expect(tracker.lastInputSource(for: board) == "japanese")
        tracker.restorePendingInputSource()
        #expect(source.selected == ["japanese"])
    }

    @Test func activationWhileEditingKeepsEditorsInputSource() {
        for name in [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification] {
            // Arrange
            let source = InputSource()
            source.current = "japanese"
            let tracker = source.tracker()
            let board = BoardID()
            tracker.boardDidFocus(board, isEnabled: true)
            tracker.canRecordInputSource = { false }
            source.current = "english"
            source.notifications.post(name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)

            // Act
            source.notifications.post(name: name, object: nil)

            // Assert
            #expect(source.current == "english")
            #expect(source.selected.isEmpty)
            #expect(tracker.lastInputSource(for: board) == "japanese")
            tracker.canRecordInputSource = { true }
            source.notifications.post(name: name, object: nil)
            #expect(source.current == "japanese")
        }
    }

    @Test func denModeDefersRestorationUntilExit() async throws {
        // Arrange
        let source = InputSource()
        let tracker = source.tracker()
        var denMode = true
        tracker.isDenMode = { denMode }
        let board = BoardID()
        tracker.setLastInputSource("japanese", for: board)

        // Act
        tracker.boardDidFocus(board, isEnabled: true)
        try await Task.sleep(for: .milliseconds(350))

        // Assert
        #expect(source.selected.isEmpty)
        denMode = false
        tracker.denModeDidChange()
        #expect(source.selected == ["japanese"])
    }

    @Test func inputFlushRestoresImmediatelyAndCancelsDelayedRestoration() async throws {
        // Arrange
        let source = InputSource()
        let tracker = source.tracker()
        let board = BoardID()
        tracker.setLastInputSource("japanese", for: board)
        tracker.isHandlingKeyboardAction = true
        tracker.boardDidFocus(board, isEnabled: true)

        // Act
        tracker.restorePendingInputSource()

        // Assert
        #expect(source.selected == ["japanese"])
        try await Task.sleep(for: .milliseconds(350))
        #expect(source.selected == ["japanese"])
    }

    @Test func notificationBeforeRestorationDoesNotOverwriteSavedSource() {
        // Arrange
        let source = InputSource()
        let tracker = source.tracker()
        let board = BoardID()
        tracker.setLastInputSource("japanese", for: board)
        tracker.isHandlingKeyboardAction = true
        tracker.boardDidFocus(board, isEnabled: true)

        // Act
        source.notifications.post(name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)

        // Assert
        #expect(tracker.lastInputSource(for: board) == "japanese")
        tracker.restorePendingInputSource()
        #expect(source.current == "japanese")
    }

    @Test func manualSourceChangeSupersedesPendingRestoration() {
        // Arrange
        let source = InputSource()
        let tracker = source.tracker()
        let board = BoardID()
        tracker.setLastInputSource("japanese", for: board)
        tracker.isHandlingKeyboardAction = true
        tracker.boardDidFocus(board, isEnabled: true)

        // Act
        source.current = "korean"
        source.notifications.post(name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)
        tracker.restorePendingInputSource()

        // Assert
        #expect(tracker.lastInputSource(for: board) == "korean")
        #expect(source.selected.isEmpty)
    }

    @Test func inactiveWindowDoesNotRestoreOrRecordAnotherWindowsSource() async throws {
        // Arrange
        let source = InputSource()
        let tracker = source.tracker()
        let board = BoardID()
        tracker.setLastInputSource("japanese", for: board)
        tracker.isHandlingKeyboardAction = true
        tracker.boardDidFocus(board, isEnabled: true)
        tracker.canRestoreInputSource = { false }

        // Act
        source.current = "korean"
        source.notifications.post(name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(350))

        // Assert
        #expect(source.selected.isEmpty)
        #expect(tracker.lastInputSource(for: board) == "japanese")
        tracker.canRestoreInputSource = { true }
        source.notifications.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        #expect(source.selected == ["japanese"])
    }

    @Test func removingBoardOrDisablingFeatureCancelsRestoration() async throws {
        for remove in [true, false] {
            // Arrange
            let source = InputSource()
            let tracker = source.tracker()
            let board = BoardID()
            tracker.setLastInputSource("japanese", for: board)
            tracker.isHandlingKeyboardAction = true
            tracker.boardDidFocus(board, isEnabled: true)

            // Act
            if remove {
                tracker.boardWillRemove(board)
            } else {
                tracker.isEnabled = { false }
            }
            try await Task.sleep(for: .milliseconds(350))

            // Assert
            #expect(source.selected.isEmpty)
        }
    }

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
