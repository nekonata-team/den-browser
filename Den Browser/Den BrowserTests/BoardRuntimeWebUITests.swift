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
            "_webView:contextMenuDidCreateDownload:",
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

    @Test func modifierClicksOpenSupportedLinkInNewBoard() {
        let url = URL(string: "https://example.com/page")

        #expect(
            SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                button: .primary,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.option, .command],
                button: .primary,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                button: .middle,
                url: url
            )
        )
        #expect(
            SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [],
                button: .middle,
                url: url
            )
        )
        #expect(
            SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.shift],
                button: .middle,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.option],
                button: .middle,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .other,
                modifierFlags: .command,
                button: .primary,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                button: .primary,
                url: URL(string: "mailto:test@example.com")
            )
        )
        #expect(
            SheetNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.command, .shift],
                button: .primary,
                url: url
            )
        )
    }

    @Test func middleClicksChooseBackgroundOrFocusedBoard() throws {
        let url = try #require(URL(string: "https://example.com/page"))
        var openedURL: URL?
        var backgroundURL: URL?
        var actions = noOpSheetNavigationActions()
        actions.onOpenBoard = { openedURL = $0 }
        actions.onOpenBoardInBackground = { backgroundURL = $0 }

        let runtime = BoardRuntime(
            board: BoardState(label: "Board", width: 320, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: SheetNavigationManager(scriptSource: ""),
            sheetScale: 100,
            sheetNavigationActions: actions,
            events: .init(
                onChange: { _, _, _ in },
                onFullscreenChange: nil,
                onDownloadFinished: { _ in },
                onDownloadFailed: { _ in }
            )
        )
        defer { runtime.dispose() }

        #expect(
            runtime.handleLinkNavigation(
                url,
                navigationType: .linkActivated,
                modifierFlags: [],
                button: .middle,
                opensNewContext: false
            )
        )
        #expect(backgroundURL == url)
        #expect(openedURL == nil)

        openedURL = nil
        backgroundURL = nil

        #expect(
            runtime.handleLinkNavigation(
                url,
                navigationType: .linkActivated,
                modifierFlags: [.shift],
                button: .middle,
                opensNewContext: false
            )
        )
        #expect(openedURL == url)
        #expect(backgroundURL == nil)
    }

    @Test func optionPrimaryClickKeepsSupportedLinkInDrawer() {
        let url = URL(string: "https://example.com/page")

        #expect(
            SheetNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: .option,
                button: .primary,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: [.option, .shift],
                button: .primary,
                url: url
            )
        )
        #expect(
            !SheetNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: .option,
                button: .primary,
                url: URL(string: "mailto:test@example.com")
            )
        )
    }

    @Test func drawerPreviewDistinguishesNewContextLinks() throws {
        let manager = SheetNavigationManager(scriptSource: "")
        let item = DrawerItem(url: try #require(URL(string: "file:///tmp/drawer-preview.html")))
        var keptURL: URL?
        var backgroundURL: URL?
        let runtime = DrawerPreviewRuntime(
            item: item,
            websiteDataStore: .nonPersistent(),
            sheetNavigation: manager,
            sheetScale: 100,
            onKeepInDrawer: { keptURL = $0 },
            onKeepInDrawerInBackground: { backgroundURL = $0 },
            onDiscard: {},
            onChange: { _, _, _ in },
            onDownloadFinished: { _ in },
            onDownloadFailed: { _ in }
        )
        defer { runtime.dispose() }

        let normalURL = try #require(URL(string: "https://example.com/normal"))
        #expect(
            !runtime.handleLinkNavigation(
                normalURL,
                navigationType: .linkActivated,
                modifierFlags: [],
                button: .primary,
                opensNewContext: false
            )
        )
        #expect(keptURL == nil)

        let targetlessURL = try #require(URL(string: "https://example.com/targetless"))
        #expect(
            runtime.handleLinkNavigation(
                targetlessURL,
                navigationType: .linkActivated,
                modifierFlags: [],
                button: .primary,
                opensNewContext: true
            )
        )
        #expect(keptURL == targetlessURL)

        let commandURL = try #require(URL(string: "https://example.com/command"))
        #expect(
            runtime.handleLinkNavigation(
                commandURL,
                navigationType: .linkActivated,
                modifierFlags: .command,
                button: .primary,
                opensNewContext: true
            )
        )
        #expect(backgroundURL == commandURL)

        let commandShiftURL = try #require(URL(string: "https://example.com/command-shift"))
        #expect(
            runtime.handleLinkNavigation(
                commandShiftURL,
                navigationType: .linkActivated,
                modifierFlags: [.command, .shift],
                button: .primary,
                opensNewContext: true
            )
        )
        #expect(keptURL == commandShiftURL)

        let optionURL = try #require(URL(string: "https://example.com/option"))
        #expect(
            runtime.handleLinkNavigation(
                optionURL,
                navigationType: .linkActivated,
                modifierFlags: .option,
                button: .primary,
                opensNewContext: false
            )
        )
        #expect(keptURL == optionURL)

        let middleURL = try #require(URL(string: "https://example.com/middle"))
        #expect(
            runtime.handleLinkNavigation(
                middleURL,
                navigationType: .linkActivated,
                modifierFlags: [],
                button: .middle,
                opensNewContext: false
            )
        )
        #expect(backgroundURL == middleURL)

        let shiftMiddleURL = try #require(URL(string: "https://example.com/shift-middle"))
        #expect(
            runtime.handleLinkNavigation(
                shiftMiddleURL,
                navigationType: .linkActivated,
                modifierFlags: [.shift],
                button: .middle,
                opensNewContext: false
            )
        )
        #expect(keptURL == shiftMiddleURL)
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
        onCopyURLSucceeded: {},
        onCopyURLFailed: {},
        onPasteURLFailed: {},
        onOpenBoardPanel: {},
        onShowOverview: {},
        onShowEssentials: {},
        onRemoveBoard: {},
        onRemoveBoardAndFocusNext: {},
        onRestoreBoard: {},
        onFocusFirstBoard: {},
        onFocusLastBoard: {},
        onGoToFirstSheet: {},
        onGoToLatestSheet: {},
        isSupportedSheetURL: SheetURLPolicy.isSupported,
        onNavigateCurrentSheet: { _ in }
    )
}
