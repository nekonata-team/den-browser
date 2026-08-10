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
            sheetNavigationActions: noOpSheetNavigationActions(),
            events: .init(
                onChange: { _, _, _ in },
                onFullscreenChange: nil,
                onDownloadFinished: { _ in },
                onDownloadFailed: { _ in }
            )
        )

        #expect(runtime.webView.navigationDelegate === runtime)
        #expect(runtime.webView.uiDelegate === runtime)
        #expect(!runtime.isLoading)
        #expect(runtime.estimatedProgress == 0)

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
            SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                buttonNumber: 0,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.option, .command],
                buttonNumber: 0,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                buttonNumber: 1,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .other,
                modifierFlags: .command,
                buttonNumber: 0,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                buttonNumber: 0,
                url: URL(string: "mailto:test@example.com")
            )
        )
        #expect(
            SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.command, .shift],
                buttonNumber: 0,
                url: url
            )
        )
    }

    @Test func optionPrimaryClickKeepsSupportedLinkInDrawer() {
        let url = URL(string: "https://example.com/page")

        #expect(
            SheetNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: .option,
                buttonNumber: 0,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: [.option, .shift],
                buttonNumber: 0,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: .option,
                buttonNumber: 0,
                url: URL(string: "mailto:test@example.com")
            )
        )
    }

    @Test func customSchemeNavigationOpensInExternalApplication() {
        #expect(
            SheetNavigationPolicy.shouldOpenExternalApplication(
                navigationType: .linkActivated,
                url: URL(string: "testapp://open/example")
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenExternalApplication(
                navigationType: .linkActivated,
                url: URL(string: "https://example.com/page")
            )
        )
        #expect(
            SheetNavigationPolicy.shouldOpenExternalApplication(
                navigationType: .other,
                url: URL(string: "testapp://open/example")
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenExternalApplication(
                navigationType: .linkActivated,
                url: URL(string: "file:///tmp/example")
            )
        )
    }

    @Test func onlyTargetlessLinkActivationsOpenInNewBoard() {
        let url = URL(string: "https://example.com/page")

        #expect(
            SheetNavigationPolicy.shouldOpenTargetlessNavigationInNewBoard(
                navigationType: .linkActivated,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenTargetlessNavigationInNewBoard(
                navigationType: .other,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenTargetlessNavigationInNewBoard(
                navigationType: .formSubmitted,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenTargetlessNavigationInNewBoard(
                navigationType: .linkActivated,
                url: URL(string: "about:blank")
            )
        )
    }
}

@MainActor
private func noOpSheetNavigationActions() -> SheetNavigationManager.Actions {
    .init(
        onOpenBoard: { _ in },
        onOpenBoardInBackground: { _ in },
        onKeepInDrawer: { _ in },
        onEditCurrentSheet: {},
        onOpenCurrentSheetInNewBoard: { _ in },
        onPasteURLInNewBoard: { _ in },
        onOpenBoardPanel: {},
        onShowOverview: {},
        onRemoveBoard: {},
        onRestoreBoard: {},
        onFocusFirstBoard: {},
        onFocusLastBoard: {},
        onGoToFirstSheet: {},
        onGoToLatestSheet: {},
        isSupportedSheetURL: SheetURLPolicy.isSupported,
        onNavigateCurrentSheet: { _ in }
    )
}
