import AppKit
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenStoreDeskPresetTests {

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

    @Test func matchingChoicesFiltersToMatchingPreset() {
        // Arrange
        let choices = sampleChoices()

        // Act
        let matched = DeskPresetSearch.matchingChoices(
            allChoices: choices,
            query: "chat",
            allowsEmptyPreset: true)

        // Assert
        #expect(matched == [choices[1]])
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
        let second = board("Notes", width: 760, url: "")
        let source = desk("Morning", boards: [first, second], focusedBoardID: second.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.isDenMode = true

        // Act
        let saveResult = store.saveFocusedDeskAsPreset(label: "  Morning  ")

        // Assert - preset captured
        #expect(saveResult == .created)
        #expect(!store.isDenMode)
        let preset = try #require(store.deskPresets.first)
        #expect(preset.label == "Morning")
        #expect(preset.boards.map(\.label) == ["Mail", "Notes"])
        #expect(preset.boards.map(\.width) == [420, 760])
        #expect(
            preset.boards[0].initialSheetURL
                == URL(string: "https://mail.example.com/inbox?label=work#today"))
        #expect(preset.boards[1].initialSheetURL == nil)
        #expect(preset.focusedBoardIndex == 1)

        // Act - instantiate new desk from preset
        store.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert - independent desk created
        let copy = try #require(store.focusedDesk)
        #expect(copy.boards.map(\.id) != source.boards.map(\.id))
        #expect(copy.boards.map(\.label) == source.boards.map(\.label))
        #expect(copy.boards.map(\.firstSheetURL) == preset.boards.map(\.initialSheetURL))
        #expect(copy.focusedBoardID == copy.boards[1].id)
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
        #expect(preset.boards.first?.content == .terminal("/tmp"))
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
        #expect(preset.boards.first?.content == .zellij("project-a"))
        #expect(store.focusedBoard?.id != zellij.id)
        #expect(store.focusedBoard?.isZellij == true)
        #expect(store.focusedBoard?.zellijSessionName == "project-a")
        #expect(store.focusedBoard?.customLabel == "Project")
    }

    @Test func personalPresetRestoresZmxBoardSession() throws {
        // Arrange
        let zmx = BoardState(width: 700, zmxSessionName: "project-a", customLabel: "Project")
        let source = desk("Development", boards: [zmx], focusedBoardID: zmx.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        // Act
        let saveResult = store.saveFocusedDeskAsPreset(label: "zmx")
        let preset = try #require(store.deskPresets.first)
        store.createDesk(label: "Copy", personalPresetID: preset.id)

        // Assert
        #expect(saveResult == .created)
        #expect(preset.boards.first?.content == .zmx("project-a"))
        #expect(store.focusedBoard?.id != zmx.id)
        #expect(store.focusedBoard?.isZmx == true)
        #expect(store.focusedBoard?.zmxSessionName == "project-a")
        #expect(store.focusedBoard?.customLabel == "Project")
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
        #expect(store.saveFocusedDeskAsPreset(label: "Routine") == .created)
        let routineID = try #require(store.deskPresets.first?.id)
        store.state.desks[0].boards[0].width = 900
        store.isDenMode = true

        // Act
        let pending = store.saveFocusedDeskAsPreset(label: " routine ")
        #expect(pending == .replacementPending)
        store.confirmDeskPresetReplacement()

        // Assert
        #expect(!store.isDenMode)
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

        // Act
        store.requestDeskPresetDeletion(routineID)
        store.confirmDeskPresetDeletion()

        // Assert
        #expect(store.deskPresets.map(\.label) == ["Other"])
    }

    @Test func finishingPresetManagementExitsDenMode() {
        // Arrange
        let source = desk("Desk", boards: [board("Board")])
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.isDenMode = true
        store.showDeskPresetManagement()

        // Act
        store.hideNewDeskPanel(exitsDenMode: true)

        // Assert
        #expect(store.temporaryContext == nil)
        #expect(!store.isDenMode)
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

        withStore(desks: [empty]) { store in
            // Act
            store.showSaveDeskPresetPanel()

            // Assert
            #expect(!store.isSaveDeskPresetPanelPresented)
        }
    }

    @Test func saveDeskPresetShowsErrorToastWhenPersistenceFails() {
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
        #expect(store.toastMessage?.message == "Could not save Desk Preset.")
        #expect(store.toastMessage?.style == ToastMessage.ToastStyle.error)
    }

    @Test func saveDeskPresetShowsSuccessToastWhenPersistenceSucceeds() {
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
        #expect(store.toastMessage?.message == "Saved Desk Preset.")
        #expect(store.toastMessage?.style == ToastMessage.ToastStyle.success)
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

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
