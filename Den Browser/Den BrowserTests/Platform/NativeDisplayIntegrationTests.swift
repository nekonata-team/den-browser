import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import SwiftUI
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct NativeDisplayIntegrationTests {
    @Test func appConstructsNotificationViewWithTheWindowModel() {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)

        // Act
        let view = NotificationListView(profileColor: .blue).environment(composition.model.notificationList)

        // Assert
        #expect(NSHostingView(rootView: view).fittingSize.height >= 0)
    }

    @Test func webResourceDisplaysThroughViewAndSurvivesViewRecreation() async throws {
        // Arrange
        let board = BoardState(label: "Web", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let runtime = session.runtimes.webRuntime(for: board)
        defer { session.runtimes.releaseRuntimes() }
        let window = TestWindow()
        defer { window.contentView = nil }

        // Act
        window.contentView = NSHostingView(rootView: NativeSurfaceView(surface: runtime.webView))
        window.contentView?.layoutSubtreeIfNeeded()
        runtime.webView.loadHTMLString("<title>Boundary</title><p>Native Web surface</p>", baseURL: nil)
        let deadline = ContinuousClock.now + .seconds(10)
        while runtime.webView.title != "Boundary", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        window.contentView = nil
        window.contentView = NSHostingView(rootView: NativeSurfaceView(surface: runtime.webView))
        window.contentView?.layoutSubtreeIfNeeded()

        // Assert
        #expect(runtime.webView.window === window)
        #expect(session.runtimes.webRuntime(for: board) === runtime)
        #expect(runtime.webView.title == "Boundary")
        let text = try await runtime.webView.evaluateJavaScript("document.body.textContent") as? String
        #expect(text == "Native Web surface")
        for resource in ["SheetDOM", "SheetNavigation", "PictureInPicture", "InspectionAgent"] {
            let url = try #require(Bundle.main.url(forResource: resource, withExtension: "js"))
            #expect(!(try String(contentsOf: url, encoding: .utf8)).isEmpty)
        }
        let dom =
            try await runtime.webView.callAsyncJavaScript(
                "return typeof window.__denSheetDOM", arguments: [:], in: nil,
                contentWorld: SheetDOMRuntime.contentWorld) as? String
        #expect(dom == "object")
    }

    @Test func terminalResourceDisplaysThroughViewAndNativeCommandsNeedNoModel() async throws {
        // Arrange
        let runtime = TerminalRuntime(
            workingDirectory: "/tmp", command: "/bin/zsh -f",
            events: .init(
                onClose: {}, onFocus: {}, onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in }, onOpenURL: { _ in }, onNotification: { _, _ in }))
        defer { runtime.dispose() }
        let window = TestWindow()
        defer { window.contentView = nil }
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let marker = "native_boundary_\(suffix)"
        // The native command entry, also used by IPC, does not construct a screen Model.
        runtime.runCommand("printf 'native_boundary_%s\\n' '\(suffix)'")

        // Act
        window.contentView = NSHostingView(rootView: NativeSurfaceView(surface: runtime.terminalView))
        window.contentView?.layoutSubtreeIfNeeded()
        let deadline = ContinuousClock.now + .seconds(10)
        while runtime.readViewportText()?.contains(marker) != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        window.contentView = nil
        window.contentView = NSHostingView(rootView: NativeSurfaceView(surface: runtime.terminalView))
        window.contentView?.layoutSubtreeIfNeeded()

        // Assert
        #expect(runtime.terminalView.window === window)
        #expect(runtime.readViewportText()?.contains(marker) == true)
    }
}
