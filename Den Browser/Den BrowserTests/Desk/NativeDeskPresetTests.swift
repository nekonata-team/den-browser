import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct NativeDeskPresetTests {
    @Test func selectionNavigationWrapsAndStartsAtTheDirectionalEdge() {
        let values = ["first", "middle", "last"]

        #expect(SelectionNavigation.next("last", among: values, by: 1) == "first")
        #expect(SelectionNavigation.next("first", among: values, by: -1) == "last")
        #expect(SelectionNavigation.next(nil, among: values, by: 1) == "first")
        #expect(SelectionNavigation.next(nil, among: values, by: -1) == "last")
        #expect(SelectionNavigation.next(nil, among: [String](), by: 1) == nil)
    }

    @Test func deskPresetSearchRanksFuzzyLabelsBeforeBoardAndHostMatches() throws {
        // Arrange
        let boards = [
            DeskPresetBoard(
                label: "Gemini Research",
                width: 520,
                initialSheetURL: URL(string: "https://docs.google.com/"),
                customLabel: "Project Chat")
        ]

        // Act
        let labelScore = try #require(
            DeskPresetSearch.score(query: "chat", label: "ChatGPT", boards: []))
        let boardScore = try #require(
            DeskPresetSearch.score(query: "gemres", label: "Research", boards: boards))
        let hostScore = try #require(
            DeskPresetSearch.score(query: "docs", label: "Research", boards: boards))
        let customLabelScore = try #require(
            DeskPresetSearch.score(query: "project", label: "Research", boards: boards))
        let missingScore = DeskPresetSearch.score(query: "claude", label: "Research", boards: boards)

        // Assert
        #expect(labelScore < boardScore)
        #expect(boardScore < hostScore)
        #expect(customLabelScore < hostScore)
        #expect(missingScore == nil)
    }

    @Test func matchingChoicesReturnsAllChoicesForWhitespaceQuery() {
        // Arrange
        let choices = sampleChoices()

        // Act
        let matched = DeskPresetSearch.matchingChoices(
            allChoices: choices,
            query: "   ",
            allowsEmptyPreset: true)

        // Assert
        #expect(matched == choices)
    }

    @Test func matchingChoicesIncludesCreateOptionAfterMatchingPresets() {
        // Arrange
        let choices = sampleChoices()

        // Act
        let matched = DeskPresetSearch.matchingChoices(
            allChoices: choices,
            query: "chat",
            allowsEmptyPreset: true)

        // Assert
        #expect(
            matched == [
                choices[1],
                DeskPresetChoice(
                    selection: .newDesk(label: "chat"),
                    label: "Create \"chat\"",
                    boards: [],
                    sourceLabel: "Empty Desk"
                ),
            ])
    }

    @Test func matchingChoicesProvidesCustomEmptyFallbackWhenAllowed() {
        // Arrange
        let choices = sampleChoices()

        // Act
        let matched = DeskPresetSearch.matchingChoices(
            allChoices: choices,
            query: "  Project X  ",
            allowsEmptyPreset: true)

        // Assert
        #expect(
            matched == [
                DeskPresetChoice(
                    selection: .newDesk(label: "Project X"),
                    label: "Create \"Project X\"",
                    boards: [],
                    sourceLabel: "Empty Desk"
                )
            ])
    }

    @Test func matchingChoicesReturnsEmptyWhenNoMatchesAndEmptyPresetNotAllowed() {
        // Arrange
        let choices = sampleChoices()

        // Act
        let matched = DeskPresetSearch.matchingChoices(
            allChoices: choices,
            query: "Project X",
            allowsEmptyPreset: false)

        // Assert
        #expect(matched.isEmpty)
    }

    @Test func personalPresetCapturesStableBoardStateAndCreatesIndependentDesk() throws {
        // Arrange
        let first = board("Mail", width: 420, url: "https://mail.example.com/inbox?label=work#today")
        let inspection = BoardState(width: 360, targetBoardID: first.id)
        let second = board("Notes", width: 760, url: "")
        let source = desk("Morning", boards: [first, inspection, second], focusedBoardID: inspection.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        // Act
        let saveResult = session.presets.saveFocusedDeskAsPreset(label: "  Morning  ")

        // Assert - preset captured
        #expect(saveResult == .created)
        #expect(!windowModel.isDenMode)
        let preset = try #require(session.resources.deskPresets.first)
        #expect(preset.label == "Morning")
        #expect(preset.boards.map(\.label) == ["Mail", "Inspection Board", "Notes"])
        #expect(preset.boards.map(\.width) == [420, 360, 760])
        #expect(
            preset.boards[0].initialSheetURL
                == URL(string: "https://mail.example.com/inbox?label=work#today"))
        #expect(preset.boards[1].kind == .inspection)
        #expect(preset.boards[1].targetBoardIndex?.rawValue == 0)
        #expect(preset.boards[2].initialSheetURL == nil)
        #expect(preset.focusedBoardIndex?.rawValue == 1)

        // Act - instantiate new desk from preset
        session.desks.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert - independent desk created
        let copy = try #require(session.navigation.focusedDesk)
        #expect(Set(copy.boards.map(\.id)).isDisjoint(with: source.boards.map(\.id)))
        #expect(copy.boards.map(\.label) == source.boards.map(\.label))
        #expect(copy.boards.map(\.firstSheetURL) == preset.boards.map(\.initialSheetURL))
        #expect(copy.boards[1].isInspection)
        #expect(copy.boards[1].sideBoardTargetBoardID == copy.boards[0].id)
        #expect(copy.boards[1].sideBoardTargetBoardID != first.id)
        #expect(copy.focusedBoardID == copy.boards[1].id)
    }

    @Test func replacingDeskFromPersonalPresetRestoresInspectionGroupAndFocus() throws {
        // Arrange
        let target = board("Target", width: 620, url: "https://example.com/")
        let inspection = BoardState(width: 360, targetBoardID: target.id)
        let presetSource = desk("Research", boards: [target, inspection], focusedBoardID: inspection.id)
        let preset = PersonalDeskPreset(label: "Research", desk: presetSource)
        let oldBoard = board("Old")
        let oldDesk = desk("Old Desk", boards: [oldBoard], focusedBoardID: oldBoard.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [oldDesk], focusedDeskID: oldDesk.id)),
                deskPresets: [preset]), configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        // Act
        let result = session.desks.replaceFocusedDesk(label: "Research Copy", personalPresetID: preset.id)
        windowModel.confirmDeskReplacement()

        // Assert
        #expect(result == .confirmationPending)
        let replaced = try #require(session.navigation.focusedDesk)
        #expect(replaced.id == oldDesk.id)
        #expect(replaced.boards.map(\.width) == [620, 360])
        #expect(Set(replaced.boards.map(\.id)).isDisjoint(with: [target.id, inspection.id, oldBoard.id]))
        #expect(replaced.boards[1].isInspection)
        #expect(replaced.boards[1].sideBoardTargetBoardID == replaced.boards[0].id)
        #expect(replaced.focusedBoardID == replaced.boards[1].id)
    }

    @Test func personalPresetRestoresTerminalAsANewBoard() throws {
        // Arrange
        let terminal = BoardState(width: 700, workingDirectory: "/tmp", customLabel: "Build")
        let source = desk("Development", boards: [terminal], focusedBoardID: terminal.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        // Act
        let saveResult = session.presets.saveFocusedDeskAsPreset(label: "Terminal")
        let preset = try #require(session.resources.deskPresets.first)
        session.desks.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert
        #expect(saveResult == .created)
        #expect(preset.boards.first?.kind == .terminal(.shell(workingDirectory: "/tmp")))
        #expect(session.navigation.focusedBoard?.id != terminal.id)
        #expect(session.navigation.focusedBoard?.terminalWorkingDirectory == "/tmp")
        #expect(session.navigation.focusedBoard?.customLabel == "Build")
    }

    @Test func personalPresetRestoresZellijBoardSession() throws {
        // Arrange
        let zellij = BoardState(width: 700, zellijSessionName: "project-a", customLabel: "Project")
        let source = desk("Development", boards: [zellij], focusedBoardID: zellij.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        // Act
        let saveResult = session.presets.saveFocusedDeskAsPreset(label: "Zellij")
        let preset = try #require(session.resources.deskPresets.first)
        session.desks.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert
        #expect(saveResult == .created)
        #expect(preset.boards.first?.kind == .terminal(.zellij(sessionName: "project-a")))
        #expect(session.navigation.focusedBoard?.id != zellij.id)
        #expect(session.navigation.focusedBoard?.isZellij == true)
        #expect(session.navigation.focusedBoard?.zellijSessionName == "project-a")
        #expect(session.navigation.focusedBoard?.customLabel == "Project")
    }

    @Test func personalPresetRestoresZmxBoardSession() throws {
        // Arrange
        let zmx = BoardState(
            width: 700,
            zmxSessionName: "project-a",
            rootSessionName: "project",
            customLabel: "Project")
        let source = desk("Development", boards: [zmx], focusedBoardID: zmx.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        // Act
        let saveResult = session.presets.saveFocusedDeskAsPreset(label: "zmx")
        let preset = try #require(session.resources.deskPresets.first)
        let restoredPreset = try JSONDecoder().decode(PersonalDeskPreset.self, from: JSONEncoder().encode(preset))
        let restoredSession = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                deskPresets: [restoredPreset]), configuration: makeTestBoardRuntimeConfiguration())
        restoredSession.desks.createDesk(label: "Copy", personalPresetID: restoredPreset.id)

        // Assert
        #expect(saveResult == .created)
        #expect(
            restoredPreset.boards.first?.kind
                == .terminal(.zmx(sessionName: "project-a", rootSessionName: "project")))
        #expect(restoredSession.navigation.focusedBoard?.id != zmx.id)
        #expect(restoredSession.navigation.focusedBoard?.isZmx == true)
        #expect(restoredSession.navigation.focusedBoard?.zmxSessionName == "project-a")
        #expect(restoredSession.navigation.focusedBoard?.zmxRootSessionName == "project")
        #expect(restoredSession.navigation.focusedBoard?.customLabel == "Project")
    }

    @Test func personalPresetRejectsReservedLabels() {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())

        // Act
        let emptyResult = session.presets.saveFocusedDeskAsPreset(label: "Empty")
        let chatGPTResult = session.presets.saveFocusedDeskAsPreset(label: "ChatGPT")

        // Assert
        #expect(emptyResult == .reservedLabel)
        #expect(chatGPTResult == .reservedLabel)
        #expect(session.resources.deskPresets.isEmpty)
    }

    @Test func personalPresetReplacementUpdatesExistingPreset() throws {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        #expect(session.presets.saveFocusedDeskAsPreset(label: "Routine") == .created)
        let routineID = try #require(session.resources.deskPresets.first?.id)
        session.resources.state.desks[0].boards[0].width = 900
        windowModel.isDenMode = true

        // Act
        let pending = session.presets.saveFocusedDeskAsPreset(label: " routine ")
        #expect(pending == .replacementPending)
        windowModel.confirmDeskPresetReplacement()

        // Assert
        #expect(!windowModel.isDenMode)
        #expect(session.resources.deskPresets.first?.id == routineID)
        #expect(session.resources.deskPresets.first?.boards[0].width == 900)
    }

    @Test func personalPresetDeletionRemovesPreset() throws {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        #expect(session.presets.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(session.presets.saveFocusedDeskAsPreset(label: "Other") == .created)
        let routineID = try #require(session.resources.deskPresets.last?.id)
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        // Act
        session.presets.requestDeskPresetDeletion(routineID)
        windowModel.confirmDeskPresetDeletion()

        // Assert
        #expect(session.resources.deskPresets.map(\.label) == ["Other"])
    }

    @Test func renamingPersonalPresetPreservesCapturedStateAndRejectsReservedOrDuplicateLabels() throws {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        #expect(session.presets.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(session.presets.saveFocusedDeskAsPreset(label: "Other") == .created)
        let presetID = try #require(session.resources.deskPresets.last?.id)
        let originalBoards = try #require(session.resources.deskPresets.last?.boards)

        // Act
        let renamed = session.presets.renameDeskPreset(presetID, to: "  Daily  ")
        let duplicate = session.presets.renameDeskPreset(presetID, to: "ＯＴＨＥＲ")
        let reserved = session.presets.renameDeskPreset(presetID, to: "ChatGPT")
        let empty = session.presets.renameDeskPreset(presetID, to: "   ")
        let preset = try #require(session.resources.deskPresets.last)

        // Assert
        #expect(renamed == .renamed)
        #expect(duplicate == .duplicateLabel)
        #expect(reserved == .reservedLabel)
        #expect(empty == .invalidLabel)
        #expect(preset.id == presetID)
        #expect(preset.label == "Daily")
        #expect(preset.boards == originalBoards)
    }

    @Test func finishingPresetManagementExitsDenMode() {
        // Arrange
        let source = desk("Desk", boards: [board("Board")])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        windowModel.showDeskPresetManagement()

        // Act
        windowModel.hideNewDeskPanel(exitsDenMode: true)

        // Assert
        #expect(windowModel.temporaryContext == nil)
        #expect(!windowModel.isDenMode)
    }

    @Test func emptyDeskCanBecomePersonalPreset() {
        // Arrange
        let empty = desk("Empty")

        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [empty]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            // Act
            let result = session.presets.saveFocusedDeskAsPreset(label: "Saved")

            // Assert
            #expect(result == .created)
            #expect(session.resources.deskPresets.count == 1)
            #expect(session.resources.deskPresets.first?.label == "Saved")
            #expect(session.resources.deskPresets.first?.boards.isEmpty == true)
            #expect(session.resources.deskPresets.first?.focusedBoardIndex == nil)
        }
    }

    @Test func saveDeskPresetPanelOpensForEmptyDesk() {
        // Arrange
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

            // Act
            windowModel.showSaveDeskPresetPanel()

            // Assert
            #expect(windowModel.isSaveDeskPresetPanelPresented)
        }
    }

    @Test func saveDeskPresetShowsErrorFeedbackWhenPersistenceFails() {
        // Arrange
        let deskState = desk("Desk", boards: [board("Board")])
        var saveCallCount = 0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id)),
                deskPresets: [],
                onDeskPresetsSave: { _ in
                    saveCallCount += 1
                    return false
                }), configuration: makeTestBoardRuntimeConfiguration())

        // Act
        let result = session.presets.saveFocusedDeskAsPreset(label: "Test Preset")

        // Assert
        #expect(result == .created)
        #expect(saveCallCount == 1)
        #expect(session.feedback.latest?.message == "Could not save Desk Preset.")
        #expect(session.feedback.latest?.severity == DenFeedback.Severity.error)
    }

    @Test func saveDeskPresetShowsSuccessFeedbackWhenPersistenceSucceeds() {
        // Arrange
        let deskState = desk("Desk", boards: [board("Board")])
        var saveCallCount = 0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id)),
                deskPresets: [],
                onDeskPresetsSave: { _ in
                    saveCallCount += 1
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())

        // Act
        let result = session.presets.saveFocusedDeskAsPreset(label: "Test Preset")

        // Assert
        #expect(result == .created)
        #expect(saveCallCount == 1)
        #expect(session.feedback.latest?.message == "Saved Desk Preset.")
        #expect(session.feedback.latest?.severity == DenFeedback.Severity.success)
    }

    @Test func saveDeskPresetSavesFacingsFromCacheAndRemovesOnDelete() throws {
        // Arrange
        let boardState = board("Board")
        let deskState = desk("Desk", boards: [boardState])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id)),
                deskPresets: [], onDeskPresetsSave: { _ in true }), configuration: makeTestBoardRuntimeConfiguration())
        let context = try #require(
            CGContext(
                data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let raster = try #require(context.makeImage())
        let sampleImage = NSImage(cgImage: raster, size: CGSize(width: 10, height: 10))
        session.resources.facingCache.setFacing(sampleImage, for: boardState.id)

        // Act - Save
        let saveResult = session.presets.saveFocusedDeskAsPreset(label: "Routine")
        #expect(saveResult == .created)

        let preset = session.resources.deskPresets.first(where: { $0.label == "Routine" })
        #expect(preset != nil)
        guard let presetID = preset?.id else { return }

        // Assert - Facing cached in PresetFacingStore
        #expect(session.resources.presetFacingStore.image(for: presetID, at: 0) != nil)

        // Act - Delete
        session.presets.deleteDeskPreset(presetID)

        // Assert - Facing removed from PresetFacingStore
        #expect(session.resources.presetFacingStore.image(for: presetID, at: 0) == nil)
    }

    private static func sampleChoices() -> [DeskPresetChoice] {
        [
            DeskPresetChoice(
                selection: .builtIn(.empty),
                label: "Empty",
                boards: [],
                sourceLabel: "Built-in"
            ),
            DeskPresetChoice(
                selection: .builtIn(.chatGPT),
                label: "ChatGPT",
                boards: BuiltInDeskPreset.chatGPT.boards,
                sourceLabel: "Built-in"
            ),
        ]
    }

    private func sampleChoices() -> [DeskPresetChoice] {
        Self.sampleChoices()
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
