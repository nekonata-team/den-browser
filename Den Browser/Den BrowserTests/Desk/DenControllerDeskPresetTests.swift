import AppKit
import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenControllerDeskPresetTests {
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
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        // Act
        let saveResult = controller.saveFocusedDeskAsPreset(label: "  Morning  ")

        // Assert - preset captured
        #expect(saveResult == .created)
        #expect(!windowModel.isDenMode)
        let preset = try #require(controller.deskPresets.first)
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
        controller.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert - independent desk created
        let copy = try #require(controller.focusedDesk)
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
        let controller = DenController(
            state: DenState(desks: [oldDesk], focusedDeskID: oldDesk.id),
            deskPresets: [preset])
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        // Act
        let result = controller.replaceFocusedDesk(label: "Research Copy", personalPresetID: preset.id)
        windowModel.confirmDeskReplacement()

        // Assert
        #expect(result == .confirmationPending)
        let replaced = try #require(controller.focusedDesk)
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
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))

        // Act
        let saveResult = controller.saveFocusedDeskAsPreset(label: "Terminal")
        let preset = try #require(controller.deskPresets.first)
        controller.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert
        #expect(saveResult == .created)
        #expect(preset.boards.first?.kind == .terminal(.shell(workingDirectory: "/tmp")))
        #expect(controller.focusedBoard?.id != terminal.id)
        #expect(controller.focusedBoard?.terminalWorkingDirectory == "/tmp")
        #expect(controller.focusedBoard?.customLabel == "Build")
    }

    @Test func personalPresetRestoresZellijBoardSession() throws {
        // Arrange
        let zellij = BoardState(width: 700, zellijSessionName: "project-a", customLabel: "Project")
        let source = desk("Development", boards: [zellij], focusedBoardID: zellij.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))

        // Act
        let saveResult = controller.saveFocusedDeskAsPreset(label: "Zellij")
        let preset = try #require(controller.deskPresets.first)
        controller.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert
        #expect(saveResult == .created)
        #expect(preset.boards.first?.kind == .terminal(.zellij(sessionName: "project-a")))
        #expect(controller.focusedBoard?.id != zellij.id)
        #expect(controller.focusedBoard?.isZellij == true)
        #expect(controller.focusedBoard?.zellijSessionName == "project-a")
        #expect(controller.focusedBoard?.customLabel == "Project")
    }

    @Test func personalPresetRestoresZmxBoardSession() throws {
        // Arrange
        let zmx = BoardState(
            width: 700,
            zmxSessionName: "project-a",
            rootSessionName: "project",
            customLabel: "Project")
        let source = desk("Development", boards: [zmx], focusedBoardID: zmx.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))

        // Act
        let saveResult = controller.saveFocusedDeskAsPreset(label: "zmx")
        let preset = try #require(controller.deskPresets.first)
        let restoredPreset = try JSONDecoder().decode(PersonalDeskPreset.self, from: JSONEncoder().encode(preset))
        let recontrollerdController = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id),
            deskPresets: [restoredPreset])
        recontrollerdController.createDesk(label: "Copy", personalPresetID: restoredPreset.id)

        // Assert
        #expect(saveResult == .created)
        #expect(
            restoredPreset.boards.first?.kind
                == .terminal(.zmx(sessionName: "project-a", rootSessionName: "project")))
        #expect(recontrollerdController.focusedBoard?.id != zmx.id)
        #expect(recontrollerdController.focusedBoard?.isZmx == true)
        #expect(recontrollerdController.focusedBoard?.zmxSessionName == "project-a")
        #expect(recontrollerdController.focusedBoard?.zmxRootSessionName == "project")
        #expect(recontrollerdController.focusedBoard?.customLabel == "Project")
    }

    @Test func personalPresetRejectsReservedLabels() {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))

        // Act
        let emptyResult = controller.saveFocusedDeskAsPreset(label: "Empty")
        let chatGPTResult = controller.saveFocusedDeskAsPreset(label: "ChatGPT")

        // Assert
        #expect(emptyResult == .reservedLabel)
        #expect(chatGPTResult == .reservedLabel)
        #expect(controller.deskPresets.isEmpty)
    }

    @Test func personalPresetReplacementUpdatesExistingPreset() throws {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        #expect(controller.saveFocusedDeskAsPreset(label: "Routine") == .created)
        let routineID = try #require(controller.deskPresets.first?.id)
        controller.storage.state.desks[0].boards[0].width = 900
        windowModel.isDenMode = true

        // Act
        let pending = controller.saveFocusedDeskAsPreset(label: " routine ")
        #expect(pending == .replacementPending)
        windowModel.confirmDeskPresetReplacement()

        // Assert
        #expect(!windowModel.isDenMode)
        #expect(controller.deskPresets.first?.id == routineID)
        #expect(controller.deskPresets.first?.boards[0].width == 900)
    }

    @Test func personalPresetDeletionRemovesPreset() throws {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        #expect(controller.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(controller.saveFocusedDeskAsPreset(label: "Other") == .created)
        let routineID = try #require(controller.deskPresets.last?.id)
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        // Act
        controller.requestDeskPresetDeletion(routineID)
        windowModel.confirmDeskPresetDeletion()

        // Assert
        #expect(controller.deskPresets.map(\.label) == ["Other"])
    }

    @Test func renamingPersonalPresetPreservesCapturedStateAndRejectsReservedOrDuplicateLabels() throws {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        #expect(controller.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(controller.saveFocusedDeskAsPreset(label: "Other") == .created)
        let presetID = try #require(controller.deskPresets.last?.id)
        let originalBoards = try #require(controller.deskPresets.last?.boards)

        // Act
        let renamed = controller.renameDeskPreset(presetID, to: "  Daily  ")
        let duplicate = controller.renameDeskPreset(presetID, to: "ＯＴＨＥＲ")
        let reserved = controller.renameDeskPreset(presetID, to: "ChatGPT")
        let empty = controller.renameDeskPreset(presetID, to: "   ")
        let preset = try #require(controller.deskPresets.last)

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
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
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

    @Test func emptyDeskCannotBecomePersonalPreset() {
        // Arrange
        let empty = desk("Empty")

        withController(desks: [empty]) { controller in
            // Act
            let result = controller.saveFocusedDeskAsPreset(label: "Saved")

            // Assert
            #expect(result == .emptyDesk)
            #expect(controller.deskPresets.isEmpty)
        }
    }

    @Test func saveDeskPresetPanelDoesNotOpenForEmptyDesk() {
        // Arrange
        let empty = desk("Empty")

        withTestWindowModel(desks: [empty]) { windowModel, _ in
            // Act
            windowModel.showSaveDeskPresetPanel()

            // Assert
            #expect(!windowModel.isSaveDeskPresetPanelPresented)
        }
    }

    @Test func saveDeskPresetShowsErrorFeedbackWhenPersistenceFails() {
        // Arrange
        let deskState = desk("Desk", boards: [board("Board")])
        var saveCallCount = 0
        let controller = DenController(
            state: DenState(desks: [deskState], focusedDeskID: deskState.id),
            deskPresets: [],
            onDeskPresetsSave: { _ in
                saveCallCount += 1
                return false
            }
        )

        // Act
        let result = controller.saveFocusedDeskAsPreset(label: "Test Preset")

        // Assert
        #expect(result == .created)
        #expect(saveCallCount == 1)
        #expect(controller.latestFeedback?.message == "Could not save Desk Preset.")
        #expect(controller.latestFeedback?.severity == DenFeedback.Severity.error)
    }

    @Test func saveDeskPresetShowsSuccessFeedbackWhenPersistenceSucceeds() {
        // Arrange
        let deskState = desk("Desk", boards: [board("Board")])
        var saveCallCount = 0
        let controller = DenController(
            state: DenState(desks: [deskState], focusedDeskID: deskState.id),
            deskPresets: [],
            onDeskPresetsSave: { _ in
                saveCallCount += 1
                return true
            }
        )

        // Act
        let result = controller.saveFocusedDeskAsPreset(label: "Test Preset")

        // Assert
        #expect(result == .created)
        #expect(saveCallCount == 1)
        #expect(controller.latestFeedback?.message == "Saved Desk Preset.")
        #expect(controller.latestFeedback?.severity == DenFeedback.Severity.success)
    }

    @Test func saveDeskPresetSavesFacingsFromCacheAndRemovesOnDelete() throws {
        // Arrange
        let boardState = board("Board")
        let deskState = desk("Desk", boards: [boardState])
        let controller = DenController(
            state: DenState(desks: [deskState], focusedDeskID: deskState.id),
            deskPresets: [],
            onDeskPresetsSave: { _ in true }
        )
        let context = try #require(
            CGContext(
                data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let raster = try #require(context.makeImage())
        let sampleImage = NSImage(cgImage: raster, size: CGSize(width: 10, height: 10))
        controller.facingCache.setFacing(sampleImage, for: boardState.id)

        // Act - Save
        let saveResult = controller.saveFocusedDeskAsPreset(label: "Routine")
        #expect(saveResult == .created)

        let preset = controller.deskPresets.first(where: { $0.label == "Routine" })
        #expect(preset != nil)
        guard let presetID = preset?.id else { return }

        // Assert - Facing cached in PresetFacingStore
        #expect(controller.presetFacingStore.image(for: presetID, at: 0) != nil)

        // Act - Delete
        controller.deleteDeskPreset(presetID)

        // Assert - Facing removed from PresetFacingStore
        #expect(controller.presetFacingStore.image(for: presetID, at: 0) == nil)
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
