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
    @Test func essentialsPanelHeightFollowsContentUntilScrollLimit() async throws {
        // Arrange
        func panelHeight(count: Int) async throws -> CGFloat {
            let essentials = (0..<count).map {
                Essential(name: "Essential \($0)", key: "a", input: "https://example.com/\($0)")
            }
            let window = TestWindow()
            defer { window.contentView = nil }
            var height: CGFloat = 0
            window.contentView = NSHostingView(
                rootView: EssentialsPrefixPanel(
                    profileColor: .blue, essentials: essentials, onSelect: { _ in }, onOpenInDrawer: { _ in }
                )
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    height = $0
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
            let deadline = ContinuousClock.now + .seconds(5)
            var stableSamples = 0
            while stableSamples < 3, ContinuousClock.now < deadline {
                let previous = height
                window.contentView?.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
                stableSamples = height > 0 && height == previous ? stableSamples + 1 : 0
            }
            #expect(stableSamples == 3)
            return height
        }

        // Act
        let one = try await panelHeight(count: 1)
        let three = try await panelHeight(count: 3)
        let thirty = try await panelHeight(count: 30)
        let sixty = try await panelHeight(count: 60)

        // Assert
        #expect(one < three)
        #expect(three < thirty)
        #expect(abs(thirty - sixty) < 1)
    }

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
