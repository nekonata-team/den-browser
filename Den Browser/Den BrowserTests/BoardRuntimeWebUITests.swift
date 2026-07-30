import Foundation
import Testing
import WebKit
@testable import Den_Browser

@MainActor
struct BoardRuntimeWebUITests {
    @Test func runtimeHandlesWebPageDialogsAndOpenPanels() {
        let runtime = BoardRuntime(
            board: BoardState(label: "Board", width: 320, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: SheetNavigationManager(scriptSource: ""),
            sheetScale: 100,
            onOpenBoard: { _ in },
            onChange: { _, _, _ in }
        )

        #expect(runtime.webView.navigationDelegate === runtime)
        #expect(runtime.webView.uiDelegate === runtime)

        let selectors = [
            "webView:decidePolicyForNavigationAction:decisionHandler:",
            "webView:decidePolicyForNavigationResponse:decisionHandler:",
            "webView:navigationAction:didBecomeDownload:",
            "webView:navigationResponse:didBecomeDownload:",
            "download:decideDestinationUsingResponse:suggestedFilename:completionHandler:",
            "downloadDidFinish:",
            "download:didFailWithError:resumeData:",
            "webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:",
            "webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:",
        ]
        #expect(selectors.allSatisfy { runtime.responds(to: NSSelectorFromString($0)) })
    }

    @Test func commandPrimaryClickOpensSupportedLinkInNewBoard() {
        let url = URL(string: "https://example.com/page")

        #expect(
            BoardRuntime.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                buttonNumber: 0,
                url: url
            )
        )
        #expect(
            !BoardRuntime.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.option, .command],
                buttonNumber: 0,
                url: url
            )
        )
        #expect(
            !BoardRuntime.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                buttonNumber: 1,
                url: url
            )
        )
        #expect(
            !BoardRuntime.shouldOpenLinkInNewBoard(
                navigationType: .other,
                modifierFlags: .command,
                buttonNumber: 0,
                url: url
            )
        )
        #expect(
            !BoardRuntime.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                buttonNumber: 0,
                url: URL(string: "mailto:test@example.com")
            )
        )
        #expect(
            BoardRuntime.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.command, .shift],
                buttonNumber: 0,
                url: url
            )
        )
    }

    @Test func optionPrimaryClickCapturesSupportedLinkInDrawer() {
        let url = URL(string: "https://example.com/page")

        #expect(
            BoardRuntime.shouldCaptureLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: .option,
                buttonNumber: 0,
                url: url
            )
        )
        #expect(
            !BoardRuntime.shouldCaptureLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: [.option, .shift],
                buttonNumber: 0,
                url: url
            )
        )
        #expect(
            !BoardRuntime.shouldCaptureLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: .option,
                buttonNumber: 0,
                url: URL(string: "mailto:test@example.com")
            )
        )
    }
}
