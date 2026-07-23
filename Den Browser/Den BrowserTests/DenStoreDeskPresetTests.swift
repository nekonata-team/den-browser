import AppKit
import Foundation
import Testing
@testable import Den_Browser

@MainActor
struct DenStoreDeskPresetTests {

    @Test func deskPresetSearchRanksFuzzyLabelsBeforeBoardAndHostMatches() throws {
        let boards = [
            DeskPresetBoard(
                label: "Gemini Research",
                width: 520,
                initialSheetURL: URL(string: "https://docs.google.com/"),
                customLabel: "Project Chat")
        ]

        let labelScore = try #require(
            DeskPresetSearch.score(query: "chat", label: "ChatGPT", boards: []))
        let boardScore = try #require(
            DeskPresetSearch.score(query: "gemres", label: "Research", boards: boards))
        let hostScore = try #require(
            DeskPresetSearch.score(query: "docs", label: "Research", boards: boards))
        let customLabelScore = try #require(
            DeskPresetSearch.score(query: "project", label: "Research", boards: boards))

        #expect(labelScore < boardScore)
        #expect(boardScore < hostScore)
        #expect(customLabelScore < hostScore)
        #expect(DeskPresetSearch.score(query: "claude", label: "Research", boards: boards) == nil)
    }

    @Test func personalPresetCapturesStableBoardStateAndCreatesIndependentDesk() throws {
        let first = board("Mail", width: 420, url: "https://mail.example.com/inbox?label=work#today")
        let second = board("Notes", width: 760, url: "")
        let source = desk("Morning", boards: [first, second], focusedBoardID: second.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        #expect(store.saveFocusedDeskAsPreset(label: "  Morning  ") == .created)
        let preset = try #require(store.deskPresets.first)
        #expect(preset.label == "Morning")
        #expect(preset.boards.map(\.label) == ["Mail", "Notes"])
        #expect(preset.boards.map(\.width) == [420, 760])
        #expect(
            preset.boards[0].initialSheetURL
                == URL(string: "https://mail.example.com/inbox?label=work#today"))
        #expect(preset.boards[1].initialSheetURL == nil)
        #expect(preset.focusedBoardIndex == 1)

        store.createDesk(label: "Copy", personalPresetID: preset.id)
        let copy = try #require(store.focusedDesk)
        #expect(copy.boards.map(\.id) != source.boards.map(\.id))
        #expect(copy.boards.map(\.label) == source.boards.map(\.label))
        #expect(copy.focusedBoardID == copy.boards[1].id)
    }

    @Test func personalPresetValidationReplacementAndDeletion() throws {
        let source = desk("Desk", boards: [board("First")])
        var saves: [[PersonalDeskPreset]] = []
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            deskPresets: [],
            onDeskPresetsSave: { saves.append($0) })

        #expect(store.saveFocusedDeskAsPreset(label: "Empty") == .reservedLabel)
        #expect(store.saveFocusedDeskAsPreset(label: "ChatGPT") == .reservedLabel)
        #expect(store.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(store.saveFocusedDeskAsPreset(label: "Other") == .created)
        #expect(store.deskPresets.map(\.label) == ["Other", "Routine"])

        let routineID = try #require(store.deskPresets.last?.id)
        store.state.desks[0].boards[0].width = 900
        #expect(store.saveFocusedDeskAsPreset(label: " routine ") == .replacementPending)
        #expect(store.deskPresets.last?.boards[0].width == 520)
        store.confirmDeskPresetReplacement()
        #expect(store.deskPresets.last?.id == routineID)
        #expect(store.deskPresets.last?.boards[0].width == 900)

        store.requestDeskPresetDeletion(routineID)
        store.confirmDeskPresetDeletion()
        #expect(store.deskPresets.map(\.label) == ["Other"])
        #expect(saves.count == 4)
    }

    @Test func emptyDeskCannotBecomePersonalPreset() {
        withStore(desks: [desk("Empty")]) { store in
            #expect(store.saveFocusedDeskAsPreset(label: "Saved") == .emptyDesk)
            #expect(store.deskPresets.isEmpty)
            store.showSaveDeskPresetPanel()
            #expect(!store.isSaveDeskPresetPanelPresented)
        }
    }

    private func withStore(desks: [DeskState], body: (DenStore) throws -> Void) rethrows {
        let store = DenStore(state: DenState(desks: desks, focusedDeskID: desks[0].id))
        try body(store)
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
