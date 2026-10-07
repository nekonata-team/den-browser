import AppKit
import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenStoreDeskPresetTests {

    @Test func selectionNavigationWrapsAndStartsAtTheDirectionalEdge() {
        let values = ["first", "middle", "last"]

        #expect(DenSelectionNavigation.next("last", among: values, by: 1) == "first")
        #expect(DenSelectionNavigation.next("first", among: values, by: -1) == "last")
        #expect(DenSelectionNavigation.next(nil, among: values, by: 1) == "first")
        #expect(DenSelectionNavigation.next(nil, among: values, by: -1) == "last")
        #expect(DenSelectionNavigation.next(nil, among: [String](), by: 1) == nil)
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
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true

        // Act
        let saveResult = store.saveFocusedDeskAsPreset(label: "  Morning  ")

        // Assert - preset captured
        #expect(saveResult == .created)
        #expect(!viewModel.isDenMode)
        let preset = try #require(store.deskPresets.first)
        #expect(preset.label == "Morning")
        #expect(preset.boards.map(\.label) == ["Mail", "Inspection Board", "Notes"])
        #expect(preset.boards.map(\.width) == [420, 360, 760])
        #expect(
            preset.boards[0].initialSheetURL
                == URL(string: "https://mail.example.com/inbox?label=work#today"))
        #expect(preset.boards[1].kind == .inspection)
        #expect(preset.boards[1].targetBoardIndex == 0)
        #expect(preset.boards[2].initialSheetURL == nil)
        #expect(preset.focusedBoardIndex == 1)

        // Act - instantiate new desk from preset
        store.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert - independent desk created
        let copy = try #require(store.focusedDesk)
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
        let store = DenStore(
            state: DenState(desks: [oldDesk], focusedDeskID: oldDesk.id),
            deskPresets: [preset])
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        // Act
        let result = store.replaceFocusedDesk(label: "Research Copy", personalPresetID: preset.id)
        viewModel.confirmDeskReplacement()

        // Assert
        #expect(result == .confirmationPending)
        let replaced = try #require(store.focusedDesk)
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
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        // Act
        let saveResult = store.saveFocusedDeskAsPreset(label: "Terminal")
        let preset = try #require(store.deskPresets.first)
        store.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert
        #expect(saveResult == .created)
        #expect(preset.boards.first?.kind == .terminal(.shell(workingDirectory: "/tmp")))
        #expect(store.focusedBoard?.id != terminal.id)
        #expect(store.focusedBoard?.terminalWorkingDirectory == "/tmp")
        #expect(store.focusedBoard?.customLabel == "Build")
    }

    @Test func personalPresetRestoresZellijBoardSession() throws {
        // Arrange
        let zellij = BoardState(width: 700, zellijSessionName: "project-a", customLabel: "Project")
        let source = desk("Development", boards: [zellij], focusedBoardID: zellij.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        // Act
        let saveResult = store.saveFocusedDeskAsPreset(label: "Zellij")
        let preset = try #require(store.deskPresets.first)
        store.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert
        #expect(saveResult == .created)
        #expect(preset.boards.first?.kind == .terminal(.zellij(sessionName: "project-a")))
        #expect(store.focusedBoard?.id != zellij.id)
        #expect(store.focusedBoard?.isZellij == true)
        #expect(store.focusedBoard?.zellijSessionName == "project-a")
        #expect(store.focusedBoard?.customLabel == "Project")
    }

    @Test func personalPresetRestoresZmxBoardSession() throws {
        // Arrange
        let zmx = BoardState(
            width: 700,
            zmxSessionName: "project-a",
            rootSessionName: "project",
            customLabel: "Project")
        let source = desk("Development", boards: [zmx], focusedBoardID: zmx.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        // Act
        let saveResult = store.saveFocusedDeskAsPreset(label: "zmx")
        let preset = try #require(store.deskPresets.first)
        let restoredPreset = try JSONDecoder().decode(PersonalDeskPreset.self, from: JSONEncoder().encode(preset))
        let restoredStore = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            deskPresets: [restoredPreset])
        restoredStore.createDesk(label: "Copy", personalPresetID: restoredPreset.id)

        // Assert
        #expect(saveResult == .created)
        #expect(
            restoredPreset.boards.first?.kind
                == .terminal(.zmx(sessionName: "project-a", rootSessionName: "project")))
        #expect(restoredStore.focusedBoard?.id != zmx.id)
        #expect(restoredStore.focusedBoard?.isZmx == true)
        #expect(restoredStore.focusedBoard?.zmxSessionName == "project-a")
        #expect(restoredStore.focusedBoard?.zmxRootSessionName == "project")
        #expect(restoredStore.focusedBoard?.customLabel == "Project")
    }

    @Test func personalPresetRejectsReservedLabels() {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        // Act
        let emptyResult = store.saveFocusedDeskAsPreset(label: "Empty")
        let chatGPTResult = store.saveFocusedDeskAsPreset(label: "ChatGPT")

        // Assert
        #expect(emptyResult == .reservedLabel)
        #expect(chatGPTResult == .reservedLabel)
        #expect(store.deskPresets.isEmpty)
    }

    @Test func personalPresetReplacementUpdatesExistingPreset() throws {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        #expect(store.saveFocusedDeskAsPreset(label: "Routine") == .created)
        let routineID = try #require(store.deskPresets.first?.id)
        store.state.desks[0].boards[0].width = 900
        viewModel.isDenMode = true

        // Act
        let pending = store.saveFocusedDeskAsPreset(label: " routine ")
        #expect(pending == .replacementPending)
        viewModel.confirmDeskPresetReplacement()

        // Assert
        #expect(!viewModel.isDenMode)
        #expect(store.deskPresets.first?.id == routineID)
        #expect(store.deskPresets.first?.boards[0].width == 900)
    }

    @Test func personalPresetDeletionRemovesPreset() throws {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        #expect(store.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(store.saveFocusedDeskAsPreset(label: "Other") == .created)
        let routineID = try #require(store.deskPresets.last?.id)
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        // Act
        store.requestDeskPresetDeletion(routineID)
        viewModel.confirmDeskPresetDeletion()

        // Assert
        #expect(store.deskPresets.map(\.label) == ["Other"])
    }

    @Test func renamingPersonalPresetPreservesCapturedStateAndRejectsReservedOrDuplicateLabels() throws {
        // Arrange
        let source = desk("Desk", boards: [board("First")])
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        #expect(store.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(store.saveFocusedDeskAsPreset(label: "Other") == .created)
        let presetID = try #require(store.deskPresets.last?.id)
        let originalBoards = try #require(store.deskPresets.last?.boards)

        // Act
        let renamed = store.renameDeskPreset(presetID, to: "  Daily  ")
        let duplicate = store.renameDeskPreset(presetID, to: "ＯＴＨＥＲ")
        let reserved = store.renameDeskPreset(presetID, to: "ChatGPT")
        let empty = store.renameDeskPreset(presetID, to: "   ")
        let preset = try #require(store.deskPresets.last)

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
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        viewModel.showDeskPresetManagement()

        // Act
        viewModel.hideNewDeskPanel(exitsDenMode: true)

        // Assert
        #expect(viewModel.temporaryContext == nil)
        #expect(!viewModel.isDenMode)
    }

    @Test func emptyDeskCannotBecomePersonalPreset() {
        // Arrange
        let empty = desk("Empty")

        withStore(desks: [empty]) { store in
            // Act
            let result = store.saveFocusedDeskAsPreset(label: "Saved")

            // Assert
            #expect(result == .emptyDesk)
            #expect(store.deskPresets.isEmpty)
        }
    }

    @Test func saveDeskPresetPanelDoesNotOpenForEmptyDesk() {
        // Arrange
        let empty = desk("Empty")

        withTestViewModel(desks: [empty]) { viewModel in
            // Act
            viewModel.showSaveDeskPresetPanel()

            // Assert
            #expect(!viewModel.isSaveDeskPresetPanelPresented)
        }
    }

    @Test func saveDeskPresetShowsErrorFeedbackWhenPersistenceFails() {
        // Arrange
        let deskState = desk("Desk", boards: [board("Board")])
        var saveCallCount = 0
        let store = DenStore(
            state: DenState(desks: [deskState], focusedDeskID: deskState.id),
            deskPresets: [],
            onDeskPresetsSave: { _ in
                saveCallCount += 1
                return false
            }
        )

        // Act
        let result = store.saveFocusedDeskAsPreset(label: "Test Preset")

        // Assert
        #expect(result == .created)
        #expect(saveCallCount == 1)
        #expect(store.latestFeedback?.message == "Could not save Desk Preset.")
        #expect(store.latestFeedback?.severity == DenFeedback.Severity.error)
    }

    @Test func saveDeskPresetShowsSuccessFeedbackWhenPersistenceSucceeds() {
        // Arrange
        let deskState = desk("Desk", boards: [board("Board")])
        var saveCallCount = 0
        let store = DenStore(
            state: DenState(desks: [deskState], focusedDeskID: deskState.id),
            deskPresets: [],
            onDeskPresetsSave: { _ in
                saveCallCount += 1
                return true
            }
        )

        // Act
        let result = store.saveFocusedDeskAsPreset(label: "Test Preset")

        // Assert
        #expect(result == .created)
        #expect(saveCallCount == 1)
        #expect(store.latestFeedback?.message == "Saved Desk Preset.")
        #expect(store.latestFeedback?.severity == DenFeedback.Severity.success)
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
