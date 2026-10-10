import DenDomain
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct BoardRuntimeWebUITests {
    @Test func runtimeConfiguresPreferencesDelegatesAndLinkActivation() {
        var activationCount = 0
        var openedURL: URL?
        var backgroundURL: URL?
        var actions = noOpSheetNavigationActions()
        actions.onOpenBoard = { openedURL = $0 }
        actions.onOpenBoardInBackground = { backgroundURL = $0 }

        let runtime = WebRuntime(
            board: BoardState(label: "Board", width: 320, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            sheetScale: 100,
            sheetNavigationActions: actions,
            events: .init(
                onChange: { _, _, _ in },
                onFullscreenChange: nil,
                onLinkActivated: { activationCount += 1 },
                onDownloadFinished: { _ in },
                onDownloadFailed: { _ in }
            )
        )
        defer { runtime.dispose() }

        #expect(runtime.webView.configuration.preferences._allowsPictureInPictureMediaPlayback)
        #expect(runtime.webView.allowsMagnification)
        #expect(runtime.webView.navigationDelegate === runtime)
        #expect(runtime.webView.uiDelegate === runtime)
        #expect(!runtime.isLoading)
        #expect(runtime.estimatedProgress == 0)

        runtime.handleLinkActivation(navigationType: .linkActivated)
        runtime.handleLinkActivation(navigationType: .other)
        #expect(activationCount == 1)

        runtime.webViewWebContentProcessDidTerminate(runtime.webView)
        #expect(runtime.didTerminateContentProcess)
        runtime.webView(runtime.webView, didCommit: nil)
        #expect(!runtime.didTerminateContentProcess)

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

        runtime.auxiliaryWindowFactory = { _ in TestWindow() }
        let auxiliary = runtime.makeAuxiliaryWebView(
            configuration: WKWebViewConfiguration(),
            sourceWebView: runtime.webView
        )
        #expect(auxiliary.uiDelegate === runtime)
        #expect(auxiliary.navigationDelegate === runtime)

        let testURL = URL(string: "https://example.com/page")!
        #expect(
            runtime.handleLinkNavigation(
                testURL,
                navigationType: .linkActivated,
                modifierFlags: [],
                button: .middle,
                opensNewContext: false
            )
        )
        #expect(backgroundURL == testURL)
        #expect(openedURL == nil)

        openedURL = nil
        backgroundURL = nil

        #expect(
            runtime.handleLinkNavigation(
                testURL,
                navigationType: .linkActivated,
                modifierFlags: [.shift],
                button: .middle,
                opensNewContext: false
            )
        )
        #expect(openedURL == testURL)
        #expect(backgroundURL == nil)
    }

    @Test func modifierClicksOpenSupportedLinkInNewBoard() {
        let url = URL(string: "https://example.com/page")

        #expect(
            WebNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                button: .primary,
                url: url
            )
        )
        #expect(
            !WebNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.option, .command],
                button: .primary,
                url: url
            )
        )
        #expect(
            !WebNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                button: .middle,
                url: url
            )
        )
        #expect(
            WebNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [],
                button: .middle,
                url: url
            )
        )
        #expect(
            WebNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.shift],
                button: .middle,
                url: url
            )
        )
        #expect(
            !WebNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.option],
                button: .middle,
                url: url
            )
        )
        #expect(
            !WebNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .other,
                modifierFlags: .command,
                button: .primary,
                url: url
            )
        )
        #expect(
            !WebNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: .command,
                button: .primary,
                url: URL(string: "mailto:test@example.com")
            )
        )
        #expect(
            WebNavigationPolicy.shouldOpenLinkInNewBoard(
                navigationType: .linkActivated,
                modifierFlags: [.command, .shift],
                button: .primary,
                url: url
            )
        )
    }

    @Test func optionPrimaryClickKeepsSupportedLinkInDrawer() {
        let url = URL(string: "https://example.com/page")

        #expect(
            WebNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: .option,
                button: .primary,
                url: url
            )
        )
        #expect(
            !WebNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: [.option, .shift],
                button: .primary,
                url: url
            )
        )
        #expect(
            !WebNavigationPolicy.shouldKeepLinkInDrawer(
                navigationType: .linkActivated,
                modifierFlags: .option,
                button: .primary,
                url: URL(string: "mailto:test@example.com")
            )
        )
    }

    @Test func drawerPreviewDistinguishesNewContextLinks() throws {
        let manager = makeTestSheetNavigationManager(scriptSource: "")
        let item = DrawerItem(url: try #require(URL(string: "file:///tmp/drawer-preview.html")))
        var keptURL: URL?
        var backgroundURL: URL?
        let runtime = WebRuntime(
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

        let popupURL = try #require(URL(string: "https://example.com/popup"))
        #expect(
            !runtime.handleLinkNavigation(
                popupURL,
                navigationType: .other,
                modifierFlags: [],
                button: nil,
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

        let selectors = [
            "webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:",
            "webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:",
            "download:decideDestinationUsingResponse:suggestedFilename:completionHandler:",
            "downloadDidFinish:",
            "download:didFailWithError:resumeData:",
        ]
        #expect(selectors.allSatisfy { runtime.responds(to: NSSelectorFromString($0)) })

        runtime.auxiliaryWindowFactory = { _ in TestWindow() }
        let popup = runtime.makeAuxiliaryWebView(
            configuration: WKWebViewConfiguration(),
            sourceWebView: runtime.webView
        )
        let window = try #require(popup.window as? TestWindow)
        #expect(window.contentView === popup)
        #expect(window.presentationRequests == 1)

        runtime.dispose()
        #expect(window.closeRequests == 1)
    }

    @Test func customSchemeNavigationOpensInExternalApplication() {
        #expect(
            WebNavigationPolicy.shouldOpenExternalApplication(
                navigationType: .linkActivated,
                url: URL(string: "testapp://open/example")
            )
        )
        #expect(
            !WebNavigationPolicy.shouldOpenExternalApplication(
                navigationType: .linkActivated,
                url: URL(string: "https://example.com/page")
            )
        )
        #expect(
            WebNavigationPolicy.shouldOpenExternalApplication(
                navigationType: .other,
                url: URL(string: "testapp://open/example")
            )
        )
        #expect(
            !WebNavigationPolicy.shouldOpenExternalApplication(
                navigationType: .linkActivated,
                url: URL(string: "file:///tmp/example")
            )
        )
    }

    @Test func onlyTargetlessLinkActivationsOpenInNewBoard() {
        let url = URL(string: "https://example.com/page")

        #expect(
            WebNavigationPolicy.shouldOpenTargetlessNavigationInNewBoard(
                navigationType: .linkActivated,
                url: url
            )
        )
        #expect(
            !WebNavigationPolicy.shouldOpenTargetlessNavigationInNewBoard(
                navigationType: .other,
                url: url
            )
        )
        #expect(
            !WebNavigationPolicy.shouldOpenTargetlessNavigationInNewBoard(
                navigationType: .formSubmitted,
                url: url
            )
        )
        #expect(
            !WebNavigationPolicy.shouldOpenTargetlessNavigationInNewBoard(
                navigationType: .linkActivated,
                url: URL(string: "about:blank")
            )
        )
    }

    @Test func downloadLifecycleHandlesSuccessFailureAndCleanup() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "download-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var finishedFilename: String?
        var failedFilename: String?
        var activityEvents: [DownloadActivityEvent] = []
        let runtime = WebRuntime(
            board: BoardState(label: "Board", width: 320, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            sheetScale: 100,
            sheetNavigationActions: noOpSheetNavigationActions(),
            events: .init(
                onChange: { _, _, _ in },
                onFullscreenChange: nil,
                onDownloadActivity: { activityEvents.append($0) },
                onDownloadFinished: { filename in finishedFilename = filename },
                onDownloadFailed: { filename in failedFilename = filename }
            )
        )

        // 1. Success case: atomic replacement
        let destinationURL = directory.appending(path: "target.pdf")
        let originalData = Data("original content".utf8)
        try originalData.write(to: destinationURL)

        let tempURL = BaseWebRuntime.temporaryDownloadURL(for: destinationURL)
        let downloadID = ObjectIdentifier(NSObject())
        let activityID = runtime.registerPendingDownload(
            for: downloadID,
            destinationURL: destinationURL,
            temporaryURL: tempURL)

        let newData = Data("new downloaded content".utf8)
        try newData.write(to: tempURL)

        #expect(try Data(contentsOf: destinationURL) == originalData)
        #expect(FileManager.default.fileExists(atPath: tempURL.path))

        let completed = runtime.completeDownload(for: downloadID)
        #expect(completed)
        #expect(finishedFilename == "target.pdf")
        #expect(
            activityEvents == [
                .started(DownloadActivity(id: activityID, filename: "target.pdf")),
                .ended(id: activityID),
            ])
        #expect(try Data(contentsOf: destinationURL) == newData)
        #expect(!FileManager.default.fileExists(atPath: tempURL.path))

        // 2. Failure case: original preserved, temp cleaned up
        let failDestinationURL = directory.appending(path: "important.pdf")
        let failOriginalData = Data("do not delete me".utf8)
        try failOriginalData.write(to: failDestinationURL)

        let failTempURL = BaseWebRuntime.temporaryDownloadURL(for: failDestinationURL)
        let failDownloadID = ObjectIdentifier(NSObject())
        runtime.registerPendingDownload(
            for: failDownloadID, destinationURL: failDestinationURL, temporaryURL: failTempURL)
        try Data("partial broken content".utf8).write(to: failTempURL)

        runtime.failDownload(for: failDownloadID)
        #expect(failedFilename == "important.pdf")
        #expect(try Data(contentsOf: failDestinationURL) == failOriginalData)
        #expect(!FileManager.default.fileExists(atPath: failTempURL.path))

        // 3. Dispose cleanup: in-progress temp file deleted
        let abandonedDestinationURL = directory.appending(path: "abandoned.pdf")
        let abandonedTempURL = BaseWebRuntime.temporaryDownloadURL(for: abandonedDestinationURL)
        let abandonedDownloadID = ObjectIdentifier(NSObject())
        runtime.registerPendingDownload(
            for: abandonedDownloadID, destinationURL: abandonedDestinationURL, temporaryURL: abandonedTempURL)
        try Data("in progress".utf8).write(to: abandonedTempURL)
        #expect(FileManager.default.fileExists(atPath: abandonedTempURL.path))

        runtime.dispose()
        #expect(!FileManager.default.fileExists(atPath: abandonedTempURL.path))
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
        isSupportedSheetURL: WebURLPolicy.isSupported,
        onNavigateCurrentSheet: { _ in }
    )
}
