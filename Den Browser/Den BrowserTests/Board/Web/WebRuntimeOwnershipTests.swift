import AppKit
import DenDomain
import DenPresentationModels
import DenViews
import Foundation
import SwiftUI
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct WebRuntimeOwnershipTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func mountingAnExistingWebRuntimeReusesItAndOnlyConnectsAnOpenWindow(disconnected: Bool) async throws {
        // Arrange
        let board = BoardState(label: "Web", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let original = DenController(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let runtime = original.webRuntime(for: board)
        defer { original.releaseRuntimes() }
        let receiver = original.storage.boardRuntimes.receivers[board.id]
        let next = DenController(
            storage: original.storage, presentedDeskID: desk.id, websiteDataStore: original.websiteDataStore,
            sheetNavigation: original.sheetNavigation, preferences: original.preferences, pasteboard: .withUniqueName(),
            canPresentDesk: { _ in true }, onDeskPresentationRequest: { _ in true }, onWillResetDen: {})
        if disconnected { next.runtimeConnection.disconnect() }
        let composition = DenWindowComposition(controller: next)
        let key = NSObject()
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let activityID = runtime.downloadHandler.registerPendingDownload(
            for: ObjectIdentifier(key), destinationURL: destination,
            temporaryURL: destination.appendingPathExtension("download"))
        let window = TestWindow()
        defer { window.contentView = nil }
        let (appeared, continuation) = AsyncStream<Void>.makeStream()

        // Act
        let view = Den_Browser.WebBoardView(
            board: board, isFocused: true, focusRequest: nil, isDragging: false, runtime: runtime,
            profileColor: .blue, width: 520, height: 400, isPointerFocusEnabled: true,
            onFocus: {}, onGoToFirst: {}, onGoBack: {}, onGoForward: {}, onRemove: {}, onDragChanged: { _ in },
            onDragEnded: { _ in }
        )
        .environment(next).environment(composition.model).environment(composition.model.deskFilter)
        .onAppear {
            Task { @MainActor in
                continuation.yield(())
                continuation.finish()
            }
        }
        window.contentView = NSHostingView(rootView: view)
        window.contentView?.layoutSubtreeIfNeeded()
        var iterator = appeared.makeAsyncIterator()
        _ = try #require(await iterator.next())

        // Assert
        #expect(original.activeDownloads.map(\.id) == (disconnected ? [activityID] : []))
        #expect(next.activeDownloads.map(\.id) == (disconnected ? [] : [activityID]))
        #expect(next.storage.webRuntimes[board.id] === runtime)
        #expect(next.storage.boardRuntimes.receivers[board.id] === receiver)
        #expect(runtime.webView.window === window)
        #expect(runtime.webView.url == nil)
    }

    @Test func downloadOwnerHandoffEndsOldPresentationBeforeStartingNewAndDoesNotReplayForTheSameOwner() {
        // Arrange
        let oldOwner = NSObject()
        let newOwner = NSObject()
        var order: [String] = []
        var newEvents: [DownloadActivityEvent] = []
        let runtime = WebRuntime(
            board: BoardState(label: "Web", width: 520, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(), sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            sheetScale: 100,
            sheetNavigationActions: .init(),
            events: .init(
                onChange: { _, _, _ in }, onFullscreenChange: nil,
                downloadActivityOwnerID: ObjectIdentifier(oldOwner),
                onDownloadActivity: { if case .ended = $0 { order.append("old.end") } }))
        defer { runtime.dispose() }
        let key = NSObject()
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let activityID = runtime.downloadHandler.registerPendingDownload(
            for: ObjectIdentifier(key), destinationURL: destination,
            temporaryURL: destination.appendingPathExtension("download"))
        let events = WebRuntime.Events(
            onChange: { _, _, _ in }, onFullscreenChange: nil,
            downloadActivityOwnerID: ObjectIdentifier(newOwner),
            onDownloadActivity: { event in
                newEvents.append(event)
                if case .started = event { order.append("new.start") }
                if case .ended = event { order.append("new.end") }
            })

        // Act
        runtime.updateOwner(sheetNavigationActions: .init(), events: events)
        runtime.updateOwner(sheetNavigationActions: .init(), events: events)
        runtime.downloadHandler.failDownload(for: ObjectIdentifier(key))

        // Assert
        #expect(order == ["old.end", "new.start", "new.end"])
        #expect(
            newEvents == [
                .started(DownloadActivity(id: activityID, filename: destination.lastPathComponent)),
                .ended(id: activityID),
            ])
    }
}
