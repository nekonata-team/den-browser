import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation
import GhosttyTerminal
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct BoardCopyTests {
    @Test func copyBoardIDCopiesLowercasedUUIDToPasteboardAndShowsFeedback() {
        let firstBoard = makeTestBoard("First")
        let source = makeTestDesk("Desk", boards: [firstBoard])
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session in
            let pasteboard = NSPasteboard.withUniqueName()
            session.boardNavigation.copyBoardID(firstBoard.id, pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == firstBoard.id.rawValue.uuidString.lowercased())
            #expect(session.feedback.latest?.message == "Copied Board ID.")
            #expect(session.feedback.latest?.severity == .success)
        }
    }

    @Test func copyBoardIDIgnoresUnknownBoardID() {
        let source = makeTestDesk("Desk", boards: [makeTestBoard("First")])
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session in
            let pasteboard = NSPasteboard.withUniqueName()
            session.boardNavigation.copyBoardID(BoardID(), pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == nil)
            #expect(session.feedback.latest == nil)
        }
    }

    @Test func copyBoardLocationCopiesWebTerminalAndSessionLocations() {
        let cases: [(BoardState, String, String)] = [
            (
                BoardState(label: "Web", width: 520, currentSheetURL: URL(string: "https://example.com/sheet")),
                "https://example.com/sheet",
                "Copied Current Sheet URL."
            ),
            (
                BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp/project"),
                "/tmp/project",
                "Copied Terminal working directory."
            ),
            (
                BoardState(label: "Zellij", width: 520, zellijSessionName: "project-a"),
                "project-a",
                "Copied Zellij session name."
            ),
            (
                BoardState(label: "zmx", width: 520, zmxSessionName: "project-b"),
                "project-b",
                "Copied zmx session name."
            ),
        ]

        for (board, expectedValue, expectedFeedback) in cases {
            // Arrange
            let source = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
            let pasteboard = NSPasteboard.withUniqueName()
            withTestSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
                )
            ) { session in
                // Act
                session.boardNavigation.copyBoardLocation(pasteboard: pasteboard)

                // Assert
                #expect(pasteboard.string(forType: .string) == expectedValue)
                #expect(session.feedback.latest?.message == expectedFeedback)
                #expect(session.feedback.latest?.severity == .success)
            }
        }
    }
}
