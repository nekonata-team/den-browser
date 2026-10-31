import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import SwiftUI
import Testing
import WebKit

@testable import DenViews
@testable import Den_Browser

@MainActor
struct BoardAlignmentTests {
    @Test(.timeLimit(.minutes(1)), arguments: [1, 12, 48], [false, true])
    func presetFocusChangesKeepVisibleBoardsPresented(boardCount: Int, replacesDesk: Bool) async throws {
        // Arrange
        let pageURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).html")
        try "<html><head><title>Preset Sheet</title></head><body>Preset Sheet</body></html>".write(
            to: pageURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: pageURL) }
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: makeNativeTestState()),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        composition.connect()
        let window = TestWindow()
        defer {
            composition.disconnect()
            window.orderOut(nil)
            window.contentView = nil
            session.runtimes.releaseRuntimes()
        }
        window.contentView = NSHostingView(
            rootView: Den_Browser.BoardStrip(
                size: CGSize(width: 720, height: 640), shouldShowHeader: true,
                profileColor: .blue, boardSpacing: 8, boardHorizontalPadding: 10,
                onOpenBoardAtEnd: { _ in }
            ).frame(width: 720, height: 640)
                .environment(session).environment(composition.model).environment(composition.model.deskFilter)
                .animation(DenMotion.feedback(reduceMotion: false), value: composition.model.temporaryContext))
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        // Act
        for iteration in 0..<6 {
            composition.model.setTemporaryContext(.newDesk)
            try await Task.sleep(for: .milliseconds(100))
            let presetBoards = (0..<boardCount).map {
                DeskPresetBoard(label: "Board \($0)", width: 320.3, initialSheetURL: pageURL)
            }
            let focusIndex = iteration.isMultiple(of: 2) ? 0 : boardCount - 1
            let oldDeskID = session.navigation.presentedDeskID
            let desk: DeskState
            if replacesDesk {
                #expect(
                    session.resources.deskLifecycle.replace(
                        oldDeskID, label: "Preset", boards: presetBoards,
                        focusedBoardIndex: BoardIndex(rawValue: focusIndex),
                        notify: session.desks.deskLifecycleNotifications()))
                desk = try #require(session.navigation.focusedDesk)
            } else {
                desk = try #require(
                    session.resources.deskLifecycle.create(
                        label: "Preset",
                        boards: presetBoards, focusedBoardIndex: BoardIndex(rawValue: focusIndex),
                        presentedDeskID: session.navigation.presentedDeskID,
                        notify: session.desks.deskLifecycleNotifications()))
            }
            // Interleave native scroll callbacks with focus changes during initial alignment.
            for index in [boardCount - 1, 0, focusIndex] {
                try await Task.sleep(for: .milliseconds(5))
                session.boardNavigation.focusBoard(desk.boards[index].id, exitsDenMode: true)
            }
            let expectedIDs = Set(
                (focusIndex == 0 ? Array(desk.boards.prefix(2)) : Array(desk.boards.suffix(2))).map(\.id))
            func isPresented(_ id: BoardID) -> Bool {
                guard let runtime = session.resources.webRuntimes[id] else { return false }
                return runtime.webView.window === window && !runtime.webView.isHidden
                    && runtime.webView.frame.width > 0 && runtime.webView.title == "Preset Sheet"
            }
            for _ in 0..<300 {
                window.contentView?.layoutSubtreeIfNeeded()
                if expectedIDs.allSatisfy(isPresented) { break }
                try await Task.sleep(for: .milliseconds(10))
            }

            // Assert
            func scrollDetails(_ view: NSView) -> [String] {
                let own =
                    (view as? NSScrollView).map {
                        ["scroll=\($0.contentView.bounds), document=\(String(describing: $0.documentView?.frame))"]
                    } ?? []
                return own + view.subviews.flatMap(scrollDetails)
            }
            let details = expectedIDs.map { id in
                guard let runtime = session.resources.webRuntimes[id] else { return "\(id): no runtime" }
                return "\(id): hidden=\(runtime.webView.isHidden), mounted=\(runtime.webView.window === window), "
                    + "frame=\(runtime.webView.frame), title=\(runtime.webView.title ?? "nil")"
            }.joined(separator: "\n")
            #expect(expectedIDs.allSatisfy(isPresented), "\(details)\n\(window.contentView.map(scrollDetails) ?? [])")
        }
    }

    @Test func resizePreviewKeepsTheFocusedBoardCenteredAcrossRepeatedWidthChanges() {
        // Arrange
        let boards = (0..<4).map { BoardState(label: "Board \($0)", width: 520, currentSheetURL: nil) }
        func parameters(width: Double) -> BoardLayout.Parameters {
            var resized = boards
            for index in resized.indices { resized[index].width = width }
            return BoardLayout.Parameters(
                centering: .always, boards: resized, maximizedBoardID: nil,
                windowWidth: 1_000, horizontalPadding: 10, spacing: 8)
        }
        let original = parameters(width: 520)
        let focusedIndex = 2
        let origin = BoardLayout.scrollTargetAfterLayoutChange(
            for: boards[focusedIndex].id, in: original, currentScrollX: 0)!
        let preview = BoardWidthPreview(
            deskID: DeskID(), scrollOffsetX: origin,
            contentWidth: BoardLayout.contentWidth(for: original), centeringRequest: 0)

        for width in [600.0, 680, 600, 360] {
            // Act
            let resized = parameters(width: width)
            let target = BoardLayout.scrollTargetAfterLayoutChange(
                for: boards[focusedIndex].id, in: resized, currentScrollX: origin)!
            let range = BoardLayout.boardContentRange(for: focusedIndex, in: resized)!
            let displayedCenter = (range.minX + range.maxX) / 2 + preview.translation(to: target) - origin

            // Assert
            #expect(abs(displayedCenter - original.windowWidth / 2) < 0.001)
            let nativeContentWidth = max(
                preview.minimumContentWidth(containerWidth: original.windowWidth),
                BoardLayout.contentWidth(for: resized))
            #expect(nativeContentWidth - original.windowWidth >= origin)
        }
        for containerWidth in [500.0, 1_000, 3_000] {
            #expect(preview.minimumContentWidth(containerWidth: containerWidth) - containerWidth >= origin)
        }
    }

    @Test func newerAlignmentRequestInvalidatesOlderCompletion() {
        let deskID = DeskID()
        let boardID = BoardID()
        let layoutKey = BoardStripLayoutKey(
            ids: [boardID],
            widths: [520],
            maximizedBoardID: nil,
            windowWidth: 1_000)
        let older = PendingBoardAlignment(
            deskID: deskID,
            boardID: boardID,
            kind: .resting(120),
            animated: false,
            layoutKey: layoutKey)
        let newer = PendingBoardAlignment(
            deskID: deskID,
            boardID: boardID,
            kind: .center,
            animated: true,
            layoutKey: layoutKey)

        #expect(!PendingBoardAlignment.isCurrent(older, in: newer))
        #expect(PendingBoardAlignment.isCurrent(newer, in: newer))
        #expect(newer.isRelevant(to: deskID, boardIDs: Set([boardID]), layoutKey: layoutKey))
        #expect(!newer.isRelevant(to: DeskID(), boardIDs: Set([boardID]), layoutKey: layoutKey))
        #expect(!newer.isRelevant(to: deskID, boardIDs: [], layoutKey: layoutKey))
    }

    @Test func pendingBoardAlignmentIsCancelledForDifferentDesk() {
        let deskA = DeskID()
        let deskB = DeskID()
        let boardID = BoardID()
        let layoutKey = BoardStripLayoutKey(
            ids: [boardID],
            widths: [520],
            maximizedBoardID: nil,
            windowWidth: 1_000)
        let pending = PendingBoardAlignment(
            deskID: deskA,
            boardID: boardID,
            kind: .center,
            animated: false,
            layoutKey: layoutKey)

        #expect(!pending.isRelevant(to: deskB, boardIDs: Set([boardID]), layoutKey: layoutKey))
        #expect(pending.isRelevant(to: deskA, boardIDs: Set([boardID]), layoutKey: layoutKey))
    }

    @Test func centeredScrollTargetCalculatedFromLayoutParametersMatchesExpectedOffset() {
        let board1 = BoardState(label: "1", width: 600, currentSheetURL: nil)
        let board2 = BoardState(label: "2", width: 600, currentSheetURL: nil)
        let boards = [board1, board2]
        let params = BoardLayout.Parameters(
            centering: .always,
            boards: boards,
            maximizedBoardID: nil,
            windowWidth: 1_000,
            horizontalPadding: 10,
            spacing: 10
        )
        let contentWidth = BoardLayout.contentWidth(for: params)

        let target0 = BoardLayout.centeredScrollX(
            for: 0,
            in: params,
            containerWidth: 1_000,
            contentWidth: contentWidth
        )
        let target1 = BoardLayout.centeredScrollX(
            for: 1,
            in: params,
            containerWidth: 1_000,
            contentWidth: contentWidth
        )

        #expect(target0 != nil)
        #expect(target1 != nil)
        #expect(target0 != target1)
    }

    @Test func insertedBoardWidthBeforeFocusedBoardIncludesItsSpacing() {
        let leftBoard = BoardID()
        let focusedBoard = BoardID()
        let insertedBoard = BoardID()
        let previous = BoardStripLayoutKey(
            ids: [leftBoard, focusedBoard],
            widths: [400, 600],
            maximizedBoardID: nil,
            windowWidth: 1_000)
        let current = BoardStripLayoutKey(
            ids: [leftBoard, insertedBoard, focusedBoard],
            widths: [400, 320, 600],
            maximizedBoardID: nil,
            windowWidth: 1_000)

        #expect(current.insertedWidth(before: focusedBoard, comparedTo: previous, spacing: 12) == 332)
        #expect(current.insertedWidth(before: leftBoard, comparedTo: previous, spacing: 12) == 0)
        #expect(current.insertedWidth(before: focusedBoard, comparedTo: current, spacing: 12) == 0)
    }

    @Test func removedBoardWidthBeforeFocusedBoardIncludesItsSpacing() {
        let leftBoard = BoardID()
        let removedBoard = BoardID()
        let focusedBoard = BoardID()
        let previous = BoardStripLayoutKey(
            ids: [leftBoard, removedBoard, focusedBoard],
            widths: [400, 320, 600],
            maximizedBoardID: nil,
            windowWidth: 1_000)
        let current = BoardStripLayoutKey(
            ids: [leftBoard, focusedBoard],
            widths: [400, 600],
            maximizedBoardID: nil,
            windowWidth: 1_000)

        #expect(previous.removedWidth(before: focusedBoard, comparedTo: current, spacing: 12) == 332)
        #expect(previous.removedWidth(before: leftBoard, comparedTo: current, spacing: 12) == 0)
    }
}
