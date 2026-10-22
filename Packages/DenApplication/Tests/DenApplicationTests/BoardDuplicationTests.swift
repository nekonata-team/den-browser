import DenApplication
import DenDomain
import Foundation
import Testing

@MainActor
struct BoardDuplicationTests {
    @Test(arguments: [false, true])
    func webCopyPreservesMetadataAndSelectsRequestedSheet(fromFirstSheet: Bool) throws {
        // Arrange
        let current = try #require(URL(string: "https://example.com/current"))
        let first = try #require(URL(string: "https://example.com/first"))
        let source = BoardState(
            label: "Source", width: 700, currentSheetURL: current, firstSheetURL: first,
            customLabel: "Custom", sheetNavigationPaused: true)

        // Act
        let decision = BoardDuplication.resolve(source, fromFirstSheet: fromFirstSheet)

        // Assert
        guard case .create(let copy) = decision else {
            Issue.record("Expected a Web copy")
            return
        }
        #expect(copy.id != source.id)
        #expect(copy.label == source.label)
        #expect(copy.customLabel == source.customLabel)
        #expect(copy.width == source.width)
        #expect(copy.sheetNavigationPaused)
        #expect(copy.currentSheetURL == (fromFirstSheet ? first : current))
        #expect(copy.firstSheetURL == (fromFirstSheet ? first : current))
    }

    @Test(arguments: [false, true])
    func terminalCopyPreservesLaunchStateWithoutReusingIdentity(zellij: Bool) {
        // Arrange
        let source =
            zellij
            ? BoardState(label: "Source", width: 700, zellijSessionName: "project", customLabel: "Custom")
            : BoardState(label: "Source", width: 700, workingDirectory: "/tmp/project", customLabel: "Custom")

        // Act
        let decision = BoardDuplication.resolve(source, fromFirstSheet: true)

        // Assert
        guard case .create(let copy) = decision else {
            Issue.record("Expected a Terminal copy")
            return
        }
        #expect(copy.id != source.id)
        #expect(copy.kind == source.kind)
        #expect(copy.width == source.width)
        #expect(copy.customLabel == source.customLabel)
    }

    @Test func zmxRequestsNativeSessionPreparation() {
        // Arrange
        let source = BoardState(width: 520, zmxSessionName: "project")

        // Act
        let decision = BoardDuplication.resolve(source)

        // Assert
        guard case .zmxSession = decision else {
            Issue.record("Expected Native zmx preparation")
            return
        }
    }

    @Test(arguments: ["side", "tutorial", "missing-first-sheet"])
    func unsupportedDuplicationDoesNotCreateABoard(kind: String) {
        // Arrange
        let source: BoardState
        switch kind {
        case "side": source = BoardState(width: 390, targetBoardID: BoardID())
        case "tutorial": source = BoardState(width: 520, tutorial: TutorialBoardState())
        default: source = BoardState(label: "Empty", width: 520, currentSheetURL: nil)
        }

        // Act
        let decision = BoardDuplication.resolve(source, fromFirstSheet: true)

        // Assert
        guard case .unavailable = decision else {
            Issue.record("Expected no new Board")
            return
        }
    }
}
