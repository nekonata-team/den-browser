import AppKit
import Testing

@testable import Den_Browser

@MainActor
struct InspectionBoardKeyTraversalTests {
    @Test(arguments: [
        (NSEvent.ModifierFlags(), "\t", false),
        (NSEvent.ModifierFlags.shift, "\u{19}", true),
        (NSEvent.ModifierFlags(), "\u{19}", true),
    ])
    func tabEventsChooseExpectedKeyViewDirection(
        modifiers: NSEvent.ModifierFlags,
        characters: String,
        movesBackward: Bool
    ) throws {
        // Arrange
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: 48
            ))

        // Act
        let direction = InspectionBoardKeyTraversal.movesBackward(for: event)

        // Assert
        #expect(direction == movesBackward)
    }

    @Test func nonTabEventsDoNotTraverseKeyViews() throws {
        // Arrange
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            ))

        // Act
        let direction = InspectionBoardKeyTraversal.movesBackward(for: event)

        // Assert
        #expect(direction == nil)
    }
}
