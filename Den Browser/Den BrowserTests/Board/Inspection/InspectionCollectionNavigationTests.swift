import DenDomain
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct InspectionCollectionNavigationTests {
    @Test func collectionCapturesStartupEventsOnlyForActiveBoardAndStopsAcrossNavigation() async throws {
        // Arrange
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let active = makeRuntime(manager)
        let inactive = makeRuntime(manager)
        defer {
            active.dispose()
            inactive.dispose()
        }
        active.auxiliaryWindowFactory = { _ in TestWindow() }
        active.startInspectionCollection(highlightColor: nil)
        #expect(
            active.webView.configuration.userContentController
                !== inactive.webView.configuration.userContentController
        )
        let auxiliary = active.makeAuxiliaryWebView(
            configuration: active.webView.configuration,
            sourceWebView: active.webView
        )
        #expect(
            auxiliary.configuration.userContentController
                !== active.webView.configuration.userContentController
        )
        auxiliary.loadHTMLString(
            """
            <!doctype html><html><head><title>Auxiliary</title></head><body><script>
              console.warn('auxiliary-console');
            </script></body></html>
            """,
            baseURL: URL(string: "https://auxiliary-inspection.test/")
        )

        // Act
        active.webView.loadHTMLString(
            """
            <!doctype html><html><head><title>Active</title></head><body><script>
              console.warn('document-start-console');
              throw new Error('document-start-error');
            </script></body></html>
            """,
            baseURL: URL(string: "https://active-inspection.test/")
        )
        inactive.webView.loadHTMLString(
            """
            <!doctype html><html><head><title>Inactive</title></head><body><script>
              console.warn('inactive-board-console');
            </script></body></html>
            """,
            baseURL: URL(string: "https://inactive-board.test/")
        )

        var activeSnapshot = InspectionPageSnapshot.empty
        for _ in 0..<200 {
            activeSnapshot = await active.readInspectionSnapshot()
            if active.webView.title == "Active"
                && activeSnapshot.events.contains(where: { $0.message.contains("document-start-console") })
                && activeSnapshot.events.contains(where: { $0.message.contains("document-start-error") })
            {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<200 where inactive.webView.title != "Inactive" {
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<200 where auxiliary.title != "Auxiliary" {
            try await Task.sleep(for: .milliseconds(10))
        }
        let auxiliaryJSON = try #require(
            try await auxiliary.evaluateJavaScript(InspectionPageScript.readSnapshot) as? String
        )
        let auxiliarySnapshot = try JSONDecoder().decode(
            InspectionPageSnapshot.self,
            from: Data(auxiliaryJSON.utf8)
        )
        let inactiveInspection =
            try await inactive.webView.evaluateJavaScript("typeof window.__denInspection") as? String

        active.stopInspection()
        active.webView.loadHTMLString(
            """
            <!doctype html><html><head><title>Stopped</title></head><body><script>
              console.error('after-stop-console');
            </script></body></html>
            """,
            baseURL: URL(string: "https://stopped-inspection.test/")
        )
        for _ in 0..<200 where active.webView.title != "Stopped" {
            try await Task.sleep(for: .milliseconds(10))
        }
        let stoppedInspection = try await active.webView.evaluateJavaScript("typeof window.__denInspection") as? String

        // Assert
        #expect(activeSnapshot.events.contains { $0.message.contains("document-start-console") })
        #expect(activeSnapshot.events.contains { $0.message.contains("document-start-error") })
        #expect(!auxiliarySnapshot.isCollecting)
        #expect(inactiveInspection == "undefined")
        #expect(stoppedInspection == "undefined")
    }

    private func makeRuntime(_ manager: SheetNavigationManager) -> WebBoardRuntime {
        WebBoardRuntime(
            board: BoardState(label: "Board", width: 360, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: manager,
            sheetScale: AppPreferences.defaultSheetScale,
            sheetNavigationActions: .init(),
            events: .init(onChange: { _, _, _ in })
        )
    }
}
