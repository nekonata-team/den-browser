import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DeskCreationTests {
    @Test func backgroundDeskCreationPreservesPresentation() {
        // Arrange
        let first = makeTestDesk("First")
        let second = makeTestDesk("Second")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second]))
            )
        ) { session, model in
            model.isDenMode = true

            // Act
            session.desks.createDesk(label: "New", preset: .empty, after: second.id, focus: false)

            // Assert
            #expect(session.resources.state.desks.map(\.label) == ["First", "Second", "New"])
            #expect(session.navigation.presentedDeskID == first.id)
            #expect(model.isDenMode)
        }
    }

    @Test func createsEmptyDeskAfterFocusedDesk() {
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("First"), makeTestDesk("Second")])
                )
            )
        ) { session, windowModel in
            windowModel.isDenMode = true
            session.desks.createDesk(label: "  Writing  ", preset: .empty)

            #expect(session.resources.state.desks.map(\.label) == ["First", "Writing", "Second"])
            #expect(session.navigation.focusedDesk?.label == "Writing")
            #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func creatingDeskCompletesTutorialDeskStep() {
        // Arrange
        let sourceDesk = makeTestDesk("First")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        #expect(session.boardOpening.openTutorialBoard())
        #expect(session.boardOpening.openBoard(input: "https://one.example/"))
        #expect(session.navigation.focusedDesk?.boards.count == 2)
        session.boardNavigation.focusNextBoard()

        // Act
        session.desks.createDesk(label: "Writing", preset: .empty)

        // Assert
        #expect(session.navigation.focusedDesk?.label == "Writing")
        #expect(
            session.resources.state.desks.flatMap(\.boards).first(where: \.isTutorial)?.tutorialCompletedSteps?
                .isSuperset(
                    of: [.openBoard, .navigateBoards, .createDesk]) == true
        )
    }

    @Test func createsChatGPTPresetWithThreeBoards() {
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [makeTestDesk("First")]))
            )
        ) { session in
            session.desks.createDesk(label: "AI", preset: .chatGPT)

            #expect(session.navigation.focusedDesk?.boards.count == 3)
            #expect(
                session.navigation.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://chatgpt.com/")
                } == true
            )
            #expect(session.navigation.focusedDesk?.boards.allSatisfy { $0.width == 520 } == true)
            #expect(
                session.navigation.focusedDesk?.focusedBoardID
                    == session.navigation.focusedDesk?.boards.first?.id
            )
        }
    }

    @Test func createsGeminiPresetWithThreeBoards() {
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [makeTestDesk("First")]))
            )
        ) { session in
            session.desks.createDesk(label: "Gemini", preset: .gemini)

            #expect(session.navigation.focusedDesk?.boards.count == 3)
            #expect(
                session.navigation.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://gemini.google.com/") && $0.width == 520
                } == true
            )
        }
    }

    @Test func deskCreationStopsAtTenDesks() {
        let desks = (1...DeskCreation.maximumDeskCount).map { makeTestDesk("Desk \($0)") }
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: desks))
            )
        ) { session in
            session.desks.createDesk(label: "Overflow", preset: .empty)

            #expect(session.resources.state.desks.count == DeskCreation.maximumDeskCount)
            #expect(!session.resources.deskLifecycle.canCreate)
        }
    }

    @Test func duplicatesNamedDeskAfterSourceWithIndependentBoardsAndPreservedConfiguration() throws {
        // Arrange
        let web = makeTestBoard("Web", width: 640, url: "https://example.com/current?q=1#section")
        let inspection = BoardState(width: 320, targetBoardID: web.id)
        let shell = BoardState(label: "Shell", width: 700, workingDirectory: "/tmp/work")
        let zmx = BoardState(label: "zmx", width: 600, zmxSessionName: "work", rootSessionName: "root")
        let source = makeTestDesk("Research", boards: [web, inspection, shell, zmx], focusedBoardID: inspection.id)
        let other = makeTestDesk("Other")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source, other], focusedDeskID: other.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let context = try #require(
            CGContext(
                data: nil,
                width: 10,
                height: 10,
                bitsPerComponent: 8,
                bytesPerRow: 40,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let raster = try #require(context.makeImage())
        session.resources.facingCache.setFacing(
            NSImage(cgImage: raster, size: CGSize(width: 10, height: 10)),
            for: web.id
        )

        // Act
        session.desks.duplicateDesk(source.id)

        // Assert
        let copy = try #require(session.navigation.focusedDesk)
        #expect(session.resources.state.desks.map(\.id) == [source.id, copy.id, other.id])
        #expect(session.resources.state.desks[0] == source)
        #expect(copy.label == source.label)
        #expect(copy.boards.count == source.boards.count)
        #expect(Set(copy.boards.map(\.id)).isDisjoint(with: source.boards.map(\.id)))
        #expect(DeskPresetBoard.capture(from: copy.boards) == DeskPresetBoard.capture(from: source.boards))
        #expect(copy.focusedBoardID == copy.boards[1].id)
        #expect(copy.boards[1].sideBoardTargetBoardID == copy.boards[0].id)
        #expect(session.resources.facingCache.image(for: copy.boards[0].id) != nil)
        #expect(session.resources.deskPresets.isEmpty)
        #expect(session.resources.webRuntimes.isEmpty)
        #expect(session.resources.terminalRuntimes.isEmpty)
        #expect(savedState == session.resources.state)
    }

    @Test func duplicatesEmptyDeskWithSameLabelAndExitsDenMode() {
        // Arrange
        let source = makeTestDesk("Empty")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session, windowModel in
            windowModel.isDenMode = true

            // Act
            session.desks.duplicateDesk(source.id)

            // Assert
            #expect(session.resources.state.desks.map(\.label) == ["Empty", "Empty"])
            #expect(session.navigation.focusedDesk?.id != source.id)
            #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func deskDuplicationDoesNotDuplicateTutorialBoard() {
        // Arrange
        let source = makeTestDesk("Learning")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        #expect(session.boardOpening.openTutorialBoard())

        // Act
        session.desks.duplicateDesk(source.id)

        // Assert
        #expect(session.resources.state.desks.flatMap(\.boards).filter(\.isTutorial).count == 1)
        #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
    }

    @Test(arguments: [false, true])
    func deskDuplicationRejectsUnknownSourceOrFullDen(atLimit: Bool) {
        // Arrange
        let desks = (1...(atLimit ? DeskCreation.maximumDeskCount : 1)).map { makeTestDesk("Desk \($0)") }
        let original = DenState(desks: desks, focusedDeskID: desks[0].id)
        var didSave = false
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(original),
                onSave: { state in
                    let callback: (DenState) -> Void = { _ in didSave = true }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        // Act
        session.desks.duplicateDesk(atLimit ? desks[0].id : DeskID())

        // Assert
        #expect(session.resources.state == original)
        #expect(!didSave)
    }

    @Test func replacingEmptyDeskAppliesImmediatelyAndEmptyPresetIsUnavailable() {
        let empty = makeTestDesk("Empty")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [empty]))
            )
        ) { session, windowModel in
            windowModel.showReplaceDeskPanel()

            #expect(session.desks.replaceFocusedDesk(label: "Still Empty", preset: .empty) == .unavailable)
            #expect(session.navigation.focusedDesk == empty)
            #expect(session.desks.replaceFocusedDesk(label: "Gemini", preset: .gemini) == .applied)

            #expect(session.navigation.focusedDesk?.id == empty.id)
            #expect(session.navigation.focusedDesk?.label == "Gemini")
            #expect(session.navigation.focusedDesk?.boards.count == 3)
            #expect(!windowModel.isReplaceDeskPanelPresented)
        }
    }
}
