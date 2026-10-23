import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct NativeDeskTests {
    @Test func backgroundDeskCreationPreservesPresentation() {
        // Arrange
        let first = desk("First")
        let second = desk("Second")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let model = denWindowComposition.model
            let session = denWindowSession

            model.isDenMode = true

            // Act
            session.desks.createDesk(label: "New", preset: .empty, after: second.id, focus: false)

            // Assert
            #expect(session.resources.state.desks.map(\.label) == ["First", "Second", "New"])
            #expect(session.navigation.presentedDeskID == first.id)
            #expect(model.isDenMode)
        }
    }

    @Test func backgroundDeskDeletionPreservesDenMode() {
        // Arrange
        let first = desk("First")
        let second = desk("Second")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let model = denWindowComposition.model
            let session = denWindowSession

            model.isDenMode = true

            // Act
            session.desks.confirmDeskDeletion(second.id)

            // Assert
            #expect(session.resources.state.desks.map(\.id) == [first.id])
            #expect(session.navigation.presentedDeskID == first.id)
            #expect(model.isDenMode)
        }
    }

    @Test func createsEmptyDeskAfterFocusedDesk() {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("First"), desk("Second")]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

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
        let sourceDesk = desk("First")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
                    of: [.openBoard, .navigateBoards, .createDesk]) == true)
    }

    @Test func createsChatGPTPresetWithThreeBoards() {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("First")]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.desks.createDesk(label: "AI", preset: .chatGPT)

            #expect(session.navigation.focusedDesk?.boards.count == 3)
            #expect(
                session.navigation.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://chatgpt.com/")
                } == true)
            #expect(session.navigation.focusedDesk?.boards.allSatisfy { $0.width == 520 } == true)
            #expect(
                session.navigation.focusedDesk?.focusedBoardID
                    == session.navigation.focusedDesk?.boards.first?.id)
        }
    }

    @Test func createsGeminiPresetWithThreeBoards() {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("First")]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.desks.createDesk(label: "Gemini", preset: .gemini)

            #expect(session.navigation.focusedDesk?.boards.count == 3)
            #expect(
                session.navigation.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://gemini.google.com/") && $0.width == 520
                } == true)
        }
    }

    @Test func deskCreationStopsAtTenDesks() {
        let desks = (1...DeskCreation.maximumDeskCount).map { desk("Desk \($0)") }
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: desks))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.desks.createDesk(label: "Overflow", preset: .empty)

            #expect(session.resources.state.desks.count == DeskCreation.maximumDeskCount)
            #expect(!session.resources.deskLifecycle.canCreate)
        }
    }

    @Test func duplicatesNamedDeskAfterSourceWithIndependentBoardsAndPreservedConfiguration() throws {
        // Arrange
        let web = board("Web", width: 640, url: "https://example.com/current?q=1#section")
        let inspection = BoardState(width: 320, targetBoardID: web.id)
        let shell = BoardState(label: "Shell", width: 700, workingDirectory: "/tmp/work")
        let zmx = BoardState(label: "zmx", width: 600, zmxSessionName: "work", rootSessionName: "root")
        let source = desk("Research", boards: [web, inspection, shell, zmx], focusedBoardID: inspection.id)
        let other = desk("Other")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source, other], focusedDeskID: other.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())
        let context = try #require(
            CGContext(
                data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let raster = try #require(context.makeImage())
        session.resources.facingCache.setFacing(
            NSImage(cgImage: raster, size: CGSize(width: 10, height: 10)), for: web.id)

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
        let source = desk("Empty")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

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
        let source = desk("Learning")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
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
        let desks = (1...(atLimit ? DeskCreation.maximumDeskCount : 1)).map { desk("Desk \($0)") }
        let original = DenState(desks: desks, focusedDeskID: desks[0].id)
        var didSave = false
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(original),
                onSave: { state in
                    let callback: (DenState) -> Void = { _ in didSave = true }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())

        // Act
        session.desks.duplicateDesk(atLimit ? desks[0].id : DeskID())

        // Assert
        #expect(session.resources.state == original)
        #expect(!didSave)
    }

    @Test func replacingPopulatedDeskRequiresConfirmationAndReleasesItsBoards() throws {
        let oldBoards = [board("First"), board("Second")]
        let replacing = desk("Research", boards: oldBoards, focusedBoardID: oldBoards[1].id)
        let other = desk("Other")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [replacing, other], focusedDeskID: replacing.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let runtime = session.runtimes.webRuntime(for: oldBoards[0])
        let restorationCandidate = RecentlyRemovedBoard(
            board: board("Removed"),
            sourceDeskID: other.id,
            sourceBoardIndex: BoardIndex(rawValue: 0))
        session.resources.recentlyRemovedBoards = [restorationCandidate]
        windowModel.toggleFocusedBoardMaximized()
        windowModel.showReplaceDeskPanel()

        let result = session.desks.replaceFocusedDesk(label: "  Morning  ", preset: .chatGPT)

        #expect(result == .confirmationPending)
        #expect(session.navigation.focusedDesk == replacing)
        if case let .replaceDesk(replacement)? = windowModel.pendingConfirmation {
            #expect(replacement.presetLabel == BuiltInDeskPreset.chatGPT.label)
        } else {
            Issue.record("Expected a desk replacement confirmation")
        }
        #expect(windowModel.isReplaceDeskPanelPresented)
        #expect(savedState == nil)

        windowModel.confirmDeskReplacement()

        let replaced = try #require(session.navigation.focusedDesk)
        #expect(replaced.id == replacing.id)
        #expect(session.resources.state.desks.map(\.id) == [replacing.id, other.id])
        #expect(replaced.label == "Morning")
        #expect(replaced.boards.count == 3)
        #expect(replaced.boards.allSatisfy { $0.currentSheetURL == URL(string: "https://chatgpt.com/") })
        #expect(Set(replaced.boards.map(\.id)).isDisjoint(with: oldBoards.map(\.id)))
        #expect(replaced.focusedBoardID == replaced.boards.first?.id)
        #expect(session.resources.webRuntimes[oldBoards[0].id] == nil)
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(runtime.webView.uiDelegate == nil)
        #expect(windowModel.maximizedBoardID == nil)
        #expect(session.resources.recentlyRemovedBoards.first?.board.id == restorationCandidate.board.id)
        #expect(!windowModel.isReplaceDeskPanelPresented)
        #expect(!windowModel.isDenMode)
        #expect(savedState == session.resources.state)
    }

    @Test func replacingDeskDiscardsPausedStateWithItsBoards() {
        let oldBoard = BoardState(
            label: "Old",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true)
        let replacing = desk("Research", boards: [oldBoard], focusedBoardID: oldBoard.id)
        let other = desk("Other")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [replacing, other], focusedDeskID: replacing.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        let composition = DenWindowComposition(session: session)

        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        _ = session.desks.replaceFocusedDesk(label: "Morning", preset: .chatGPT)
        windowModel.confirmDeskReplacement()

        #expect(!session.resources.state.desks.flatMap(\.boards).contains { $0.id == oldBoard.id })
    }

    @Test func replacingDeskInvalidatesReferencesToRemovedBoards() {
        // Arrange
        let oldBoards = [board("First"), board("Second")]
        var replacing = desk("Research", boards: oldBoards, focusedBoardID: oldBoards[1].id)
        replacing.anchorBoardID = oldBoards[0].id
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [replacing], focusedDeskID: replacing.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.navigation.anchorJumpOriginBoardIDByDesk[replacing.id] = oldBoards[1].id
        _ = session.boardNavigation.prepareBoardLinkFocus(oldBoards[1].id)
        windowModel.overview.selectBoard(oldBoards[1].id)
        windowModel.showReplaceDeskPanel()
        windowModel.openBoard.afterBoardID = oldBoards[0].id
        _ = session.desks.replaceFocusedDesk(label: "Morning", preset: .chatGPT)

        // Act
        windowModel.confirmDeskReplacement()

        // Assert
        #expect(session.navigation.focusedDesk?.anchorBoardID == nil)
        #expect(session.navigation.anchorJumpOriginBoardIDByDesk[replacing.id] == nil)
        #expect(windowModel.openBoard.afterBoardID == nil)
        #expect(windowModel.pendingBoardLinkFocus == nil)
        #expect(windowModel.overview.selectionDeskID == nil)
        #expect(windowModel.overview.selectionBoardID == nil)
    }

    @Test func cancellingDeskReplacementKeepsDeskAndPanel() {
        let existing = board("Existing")
        let original = desk("Original", boards: [existing])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [original]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.showReplaceDeskPanel()
            #expect(session.desks.replaceFocusedDesk(label: "AI", preset: .gemini) == .confirmationPending)

            windowModel.cancelConfirmation()

            #expect(session.navigation.focusedDesk == original)
            #expect(windowModel.pendingConfirmation == nil)
            #expect(windowModel.isReplaceDeskPanelPresented)
        }
    }

    @Test func replacingEmptyDeskAppliesImmediatelyAndEmptyPresetIsUnavailable() {
        let empty = desk("Empty")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [empty]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

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

    @Test func deletingEmptyDeskFocusesPreviousDeskWhenAvailable() {
        let first = desk("First")
        let empty = desk("Empty")
        let third = desk("Third")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, empty, third]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.boardNavigation.focusDesk(empty.id)
            windowModel.isDenMode = true
            let initialSuppression = windowModel.boardMutationAnimationSuppressionRequest
            session.desks.deleteFocusedDesk()

            #expect(session.resources.state.desks.map(\.id) == [first.id, third.id])
            #expect(session.navigation.focusedDesk?.id == first.id)
            #expect(!windowModel.isDenMode)
            #expect(windowModel.boardMutationAnimationSuppressionRequest == initialSuppression + 1)
        }
    }

    @Test func deletingFirstDeskFocusesNextDeskWhenPreviousDeskIsUnavailable() {
        let first = desk("First")
        let second = desk("Second")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.desks.deleteFocusedDesk()

            #expect(session.resources.state.desks.map(\.id) == [second.id])
            #expect(session.navigation.focusedDesk?.id == second.id)
        }
    }

    @Test func confirmingDeletionOfUnfocusedDeskClearsPreviousFocusedDeskID() {
        let first = desk("First")
        let secondBoard = board("SecondBoard")
        let second = desk("Second", boards: [secondBoard])
        let third = desk("Third")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second, third]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.boardNavigation.focusDesk(second.id)
            session.desks.deleteFocusedDesk()
            if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
                #expect(pending.id == second.id)
            } else {
                Issue.record("Expected a desk deletion confirmation")
            }

            // Switch to third desk, then confirm deletion of second desk
            session.boardNavigation.focusDesk(third.id)
            #expect(session.navigation.previousFocusedDeskID == second.id)

            let initialSuppression = windowModel.boardMutationAnimationSuppressionRequest
            windowModel.confirmDeskDeletion()
            #expect(session.resources.state.desks.map(\.id) == [first.id, third.id])
            #expect(session.navigation.previousFocusedDeskID == nil)
            #expect(windowModel.boardMutationAnimationSuppressionRequest == initialSuppression + 1)
        }
    }

    @Test func returnToPreviousDeskTogglesBetweenMostRecentDesks() {
        let first = desk("First")
        let second = desk("Second")
        let third = desk("Third")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [first, second, third], focusedDeskID: first.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        session.boardNavigation.focusDesk(second.id)
        session.boardNavigation.focusDesk(third.id)
        session.boardNavigation.returnToPreviousDesk()
        #expect(session.navigation.focusedDesk?.id == second.id)

        session.boardNavigation.returnToPreviousDesk()
        #expect(session.navigation.focusedDesk?.id == third.id)
    }

    @Test func normalizedPersistedStateEnsuresFocusedObjects() {
        let boardItem = board("Board")
        let tutorialBoard = BoardState(
            label: "Tutorial",
            width: 520,
            tutorial: TutorialBoardState())
        var first = desk(
            "First",
            boards: [tutorialBoard, boardItem],
            focusedBoardID: tutorialBoard.id)
        first.anchorBoardID = tutorialBoard.id
        first.scrollOffsetX = 80
        let second = desk("Second")
        let tutorialOnlyBoard = BoardState(
            label: "Tutorial",
            width: 520,
            tutorial: TutorialBoardState())
        let tutorialOnlyDesk = desk(
            "Tutorial only",
            boards: [tutorialOnlyBoard],
            focusedBoardID: tutorialOnlyBoard.id)
        let rawState = DenState(desks: [second, first, tutorialOnlyDesk], focusedDeskID: DeskID())

        let normalized = DenStateNormalization.normalize(rawState)
        #expect(normalized.focusedDeskID == second.id)
        #expect(normalized.desks[1].focusedBoardID == boardItem.id)
        #expect(normalized.desks[1].boards.map(\.id) == [boardItem.id])
        #expect(normalized.desks[1].anchorBoardID == nil)
        #expect(normalized.desks[1].scrollOffsetX == nil)
        #expect(normalized.desks[2].boards.isEmpty)
        #expect(normalized.desks[2].focusedBoardID == nil)
    }

    @Test func focusDeskByNumberDelegatesToFocusDesk() {
        let first = desk("First")
        let second = desk("Second")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [first, second], focusedDeskID: first.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.isDenMode = true
        session.boardNavigation.focusDesk(number: 2)
        #expect(session.navigation.focusedDesk?.id == second.id)
        #expect(!windowModel.isDenMode)
    }

    @Test func deskLinkExportPreservesBoardOrderAndSkipsEmptyBoards() throws {
        let first = BoardState(
            label: "First [Reference]",
            width: 520,
            currentSheetURL: URL(string: "https://first.example/"))
        let empty = BoardState(label: "Empty", width: 520, currentSheetURL: nil)
        let second = BoardState(
            label: "Second",
            width: 520,
            currentSheetURL: URL(string: "https://second.example/path"))
        let desk = DeskState(label: "Research", boards: [first, empty, second])

        let expected = [
            "# Research",
            "",
            "- [First \\[Reference\\]](<https://first.example/>)",
            "- [Second](<https://second.example/path>)",
            "",
        ].joined(separator: "\n")
        #expect(DeskLinkExport.markdown(for: desk) == expected)
    }

    @Test func deskDragReordersPersistedDesksWithoutChangingTheirContents() {
        let firstBoard = board("First Board")
        let secondBoard = board("Second Board")
        let first = desk("First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let second = desk("Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let third = desk("Third")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [first, second, third], focusedDeskID: first.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())

        #expect(session.resources.deskMovement.beginDrag(second.id))
        session.resources.deskMovement.preview(second.id, to: DeskIndex(rawValue: 2))
        session.runtimes.updateBoard(
            boardID: secondBoard.id,
            url: URL(string: "https://updated.example/"),
            title: "Updated title")

        #expect(savedState == nil)

        session.resources.deskMovement.finishDrag()

        #expect(session.resources.state.desks.map(\.id) == [first.id, third.id, second.id])
        #expect(session.navigation.focusedDesk?.id == first.id)
        #expect(session.resources.state.desks[2].boards.map(\.id) == [secondBoard.id])
        #expect(session.resources.state.desks[2].focusedBoardID == secondBoard.id)
        #expect(
            session.resources.state.desks[2].boards[0].currentSheetURL == URL(string: "https://updated.example/"))
        #expect(session.resources.state.desks[2].boards[0].label == "Updated title")
        #expect(savedState == session.resources.state)

        session.resources.deskMovement.preview(second.id, to: DeskIndex(rawValue: 2))
        #expect(session.resources.state.desks.map(\.id) == [first.id, third.id, second.id])
    }

    @Test func movingDeskByAccessibilityActionReordersOneStepAndPreservesFocus() {
        let first = desk("First")
        let second = desk("Second")
        let third = desk("Third")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [first, second, third], focusedDeskID: second.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        session.resources.deskMovement.move(first.id, by: 1)

        #expect(session.resources.state.desks.map(\.id) == [second.id, first.id, third.id])
        #expect(session.navigation.focusedDesk?.id == second.id)

        session.resources.deskMovement.move(third.id, by: 1)
        #expect(session.resources.state.desks.map(\.id) == [second.id, first.id, third.id])

        #expect(session.resources.deskMovement.beginDrag(first.id))
        session.resources.deskMovement.move(third.id, by: -1)
        #expect(session.resources.state.desks.map(\.id) == [second.id, first.id, third.id])
        session.resources.deskMovement.finishDrag()
    }

    @Test func cancellingDeskDragPersistsRestoredOrderAfterBoardUpdate() {
        let firstBoard = board("First Board")
        let secondBoard = board("Second Board")
        let first = desk("First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let second = desk("Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let third = desk("Third")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [first, second, third], focusedDeskID: first.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())

        #expect(session.resources.deskMovement.beginDrag(second.id))
        session.resources.deskMovement.preview(second.id, to: DeskIndex(rawValue: 2))
        session.runtimes.updateBoard(
            boardID: secondBoard.id,
            url: URL(string: "https://updated.example/"),
            title: "Updated title")
        #expect(savedState == nil)

        session.resources.deskMovement.restoreOrder([first.id, second.id, third.id])
        session.resources.deskMovement.finishDrag()

        #expect(session.resources.state.desks.map(\.id) == [first.id, second.id, third.id])
        #expect(
            session.resources.state.desks[1].boards[0].currentSheetURL == URL(string: "https://updated.example/"))
        #expect(session.resources.state.desks[1].boards[0].label == "Updated title")
        #expect(savedState == session.resources.state)
    }

    @Test func deletingDeskWithBoardsRequiresConfirmation() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [populated, empty]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.desks.deleteFocusedDesk()

            #expect(session.resources.state.desks.count == 2)
            if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
                #expect(pending.id == populated.id)
            } else {
                Issue.record("Expected a desk deletion confirmation")
            }

            session.boardNavigation.focusDesk(empty.id)
            windowModel.confirmDeskDeletion()
            #expect(session.resources.state.desks.map(\.id) == [empty.id])
            #expect(session.navigation.focusedDesk?.id == empty.id)
            #expect(windowModel.pendingConfirmation == nil)
        }
    }

    @Test func confirmingDeskDeletionExitsDenModeAfterSuccessfulDeletion() {
        let populated = desk("Populated", boards: [board("Board")])
        let empty = desk("Empty")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [populated, empty]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.isDenMode = true
            session.desks.deleteFocusedDesk()

            #expect(windowModel.isDenMode)
            windowModel.confirmDeskDeletion()

            #expect(!windowModel.isDenMode)
        }
    }

    @Test func cancellingDeskDeletionKeepsBoards() {
        let populated = desk("Populated", boards: [board("Board")])
        let empty = desk("Empty")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [populated, empty]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.desks.deleteFocusedDesk()
            windowModel.cancelConfirmation()

            #expect(session.resources.state.desks.map(\.id) == [populated.id, empty.id])
            #expect(windowModel.pendingConfirmation == nil)
        }
    }

    @Test func deletingDeskDisposesItsBoardRuntimes() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [populated, empty]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            let runtime = session.runtimes.webRuntime(for: board)
            session.desks.deleteFocusedDesk()

            windowModel.confirmDeskDeletion()

            #expect(session.resources.webRuntimes[board.id] == nil)
            #expect(runtime.webView.navigationDelegate == nil)
            #expect(runtime.webView.uiDelegate == nil)
        }
    }

    @Test func deletingDeskDiscardsItsPausedBoardState() {
        let removedBoard = BoardState(
            label: "Removed",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true)
        let populated = desk("Populated", boards: [removedBoard], focusedBoardID: removedBoard.id)
        let empty = desk("Empty")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [populated, empty], focusedDeskID: populated.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        session.desks.deleteFocusedDesk()
        windowModel.confirmDeskDeletion()

        #expect(!session.resources.state.desks.flatMap(\.boards).contains { $0.id == removedBoard.id })
    }

    @Test func lastDeskCannotBeDeleted() {
        let onlyDesk = desk("Only")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [onlyDesk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            session.desks.deleteFocusedDesk()

            #expect(session.resources.state.desks.count == 1)
            #expect(windowModel.pendingConfirmation == nil)
        }
    }

    @Test func digitDeskMovementFocusesAndMovesToNumberedDesk() {
        let moving = board("Moving")
        let targetBoard = board("Target")
        let source = desk("One", boards: [moving])
        let target = desk("Two", boards: [targetBoard])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, target]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardNavigation.moveFocusedBoard(toDeskNumber: 2)

            #expect(session.navigation.focusedDesk?.id == target.id)
            #expect(session.resources.state.desks[1].boards.map(\.id) == [targetBoard.id, moving.id])

            session.boardNavigation.focusDesk(number: 1)
            #expect(session.navigation.focusedDesk?.id == source.id)
        }
    }

    @Test func deskRenaming() {
        let firstBoard = board("Google")
        let desk1 = desk("Main", boards: [firstBoard], focusedBoardID: firstBoard.id)

        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk1]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            // 1. Enter Den Mode, show rename panel
            windowModel.isDenMode = true
            windowModel.showRenameDeskPanel()
            #expect(windowModel.isRenameDeskPanelPresented)

            // 2. Rename the desk to a custom name
            session.desks.renameFocusedDesk(to: "Web Search")
            #expect(!windowModel.isRenameDeskPanelPresented)
            #expect(session.navigation.focusedDesk?.label == "Web Search")

            // 3. Rename with empty name should be ignored (keep old name)
            windowModel.showRenameDeskPanel()
            session.desks.renameFocusedDesk(to: "")
            #expect(!windowModel.isRenameDeskPanelPresented)
            #expect(session.navigation.focusedDesk?.label == "Web Search")
        }
    }

    @Test func savesAndRetrievesDeskScrollOffset() {
        let deskA = desk("Desk A")
        let deskB = desk("Desk B")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [deskA, deskB]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            #expect(session.desks.deskScrollOffset(for: deskA.id) == nil)

            session.desks.saveDeskScrollOffset(420.5, for: deskA.id)
            #expect(session.desks.deskScrollOffset(for: deskA.id) == 420.5)
            #expect(session.desks.deskScrollOffset(for: deskB.id) == nil)

            session.desks.saveDeskScrollOffset(120.0, for: deskB.id)
            #expect(session.desks.deskScrollOffset(for: deskA.id) == 420.5)
            #expect(session.desks.deskScrollOffset(for: deskB.id) == 120.0)
        }
    }

    @Test func copyDeskIDCopiesLowercasedUUIDToPasteboardAndShowsFeedback() {
        let deskA = desk("Desk A")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [deskA]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            let pasteboard = NSPasteboard.withUniqueName()
            session.desks.copyDeskID(deskA.id, pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == deskA.id.rawValue.uuidString.lowercased())
            #expect(session.feedback.latest?.message == "Copied Desk ID.")
            #expect(session.feedback.latest?.severity == .success)
        }
    }

    @Test func copyDeskIDIgnoresUnknownDeskID() {
        let deskA = desk("Desk A")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [deskA]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            let pasteboard = NSPasteboard.withUniqueName()
            session.desks.copyDeskID(DeskID(), pasteboard: pasteboard)

            #expect(pasteboard.string(forType: .string) == nil)
            #expect(session.feedback.latest == nil)
        }
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
