import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct BoardRuntimeWebUITests {
    @Test func runtimeEnablesNativePictureInPicture() {
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
        defer { runtime.dispose() }

        #expect(runtime.webView.configuration.preferences._allowsPictureInPictureMediaPlayback)
    }

    @Test func runtimeEnablesNativeMagnification() {
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
        defer { runtime.dispose() }

        #expect(runtime.webView.allowsMagnification)
    }

    @Test func runtimeReportsNativeLinkActivationOnly() {
        var activationCount = 0
        let runtime = BoardRuntime(
            board: BoardState(label: "Board", width: 320, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: SheetNavigationManager(scriptSource: ""),
            sheetScale: 100,
            sheetNavigationActions: noOpSheetNavigationActions(),
            events: .init(
                onChange: { _, _, _ in },
                onFullscreenChange: nil,
                onLinkActivated: { activationCount += 1 },
                onDownloadFinished: { _ in },
                onDownloadFailed: { _ in }
            )
        )
        defer { runtime.dispose() }

        runtime.handleLinkActivation(navigationType: .linkActivated)
        runtime.handleLinkActivation(navigationType: .other)

        #expect(activationCount == 1)
    }

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
        defer { runtime.dispose() }

        #expect(runtime.webView.navigationDelegate === runtime)
        #expect(runtime.webView.uiDelegate === runtime)
        #expect(!runtime.isLoading)
        #expect(runtime.estimatedProgress == 0)

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
    }

    @Test func drawerPreviewDisposesAuxiliaryPopupWindow() throws {
        let manager = SheetNavigationManager(scriptSource: "")
        let runtime = DrawerPreviewRuntime(
            item: DrawerItem(url: try #require(URL(string: "file:///tmp/drawer-preview.html"))),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: manager,
            sheetScale: 100,
            onKeepInDrawer: { _ in },
            onKeepInDrawerInBackground: { _ in },
            onDiscard: {},
            onChange: { _, _, _ in },
            onDownloadFinished: { _ in },
            onDownloadFailed: { _ in }
        )
        let popup = runtime.makeAuxiliaryWebView(
            configuration: WKWebViewConfiguration(),
            sourceWebView: runtime.webView
        )
        let popupWindow = try #require(popup.window)
        #expect(popupWindow.contentView === popup)

        runtime.dispose()

        #expect(!popupWindow.isVisible)
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

    @Test func downloadPreservesExistingFileUntilFinishedAndReplacesAtomically() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "download-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destinationURL = directory.appending(path: "target.pdf")
        let originalData = Data("original content".utf8)
        try originalData.write(to: destinationURL)

        var finishedFilename: String?
        var activityEvents: [DownloadActivityEvent] = []
        let runtime = BoardRuntime(
            board: BoardState(label: "Board", width: 320, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: SheetNavigationManager(scriptSource: ""),
            sheetScale: 100,
            sheetNavigationActions: noOpSheetNavigationActions(),
            events: .init(
                onChange: { _, _, _ in },
                onFullscreenChange: nil,
                onDownloadActivity: { activityEvents.append($0) },
                onDownloadFinished: { filename in finishedFilename = filename },
                onDownloadFailed: { _ in }
            )
        )
        defer { runtime.dispose() }

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

        // Act
        let completed = runtime.completeDownload(for: downloadID)

        // Assert
        #expect(completed)
        #expect(finishedFilename == "target.pdf")
        #expect(
            activityEvents == [
                .started(DownloadActivity(id: activityID, filename: "target.pdf")),
                .ended(id: activityID),
            ])
        #expect(try Data(contentsOf: destinationURL) == newData)
        #expect(!FileManager.default.fileExists(atPath: tempURL.path))
    }

    @Test func downloadProgressUsesIndeterminateStateUntilTotalSizeIsKnown() {
        // Arrange
        let indeterminate = Progress(totalUnitCount: -1)
        let determinate = Progress(totalUnitCount: 4)
        determinate.completedUnitCount = 1

        // Act
        let unknownFraction = BaseWebRuntime.downloadProgressFraction(indeterminate)
        let knownFraction = BaseWebRuntime.downloadProgressFraction(determinate)

        // Assert
        #expect(unknownFraction == nil)
        #expect(knownFraction == 0.25)
    }

    @Test func downloadFailureKeepsOriginalFileAndDeletesTemporaryFile() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "download-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destinationURL = directory.appending(path: "important.pdf")
        let originalData = Data("do not delete me".utf8)
        try originalData.write(to: destinationURL)

        var failedFilename: String?
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
                onDownloadFailed: { filename in failedFilename = filename }
            )
        )
        defer { runtime.dispose() }

        let tempURL = BaseWebRuntime.temporaryDownloadURL(for: destinationURL)
        let downloadID = ObjectIdentifier(NSObject())
        runtime.registerPendingDownload(for: downloadID, destinationURL: destinationURL, temporaryURL: tempURL)

        let partialData = Data("partial broken content".utf8)
        try partialData.write(to: tempURL)

        // Act
        runtime.failDownload(for: downloadID)

        // Assert
        #expect(failedFilename == "important.pdf")
        #expect(try Data(contentsOf: destinationURL) == originalData)
        #expect(!FileManager.default.fileExists(atPath: tempURL.path))
    }

    @Test func runtimeDisposeCleansUpUnfinishedTemporaryDownloadFiles() throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "download-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destinationURL = directory.appending(path: "abandoned.pdf")
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

        let tempURL = BaseWebRuntime.temporaryDownloadURL(for: destinationURL)
        let downloadID = ObjectIdentifier(NSObject())
        runtime.registerPendingDownload(for: downloadID, destinationURL: destinationURL, temporaryURL: tempURL)
        try Data("in progress".utf8).write(to: tempURL)
        #expect(FileManager.default.fileExists(atPath: tempURL.path))

        // Act
        runtime.dispose()

        // Assert
        #expect(!FileManager.default.fileExists(atPath: tempURL.path))
    }

    @Test func drawerPreviewRuntimeImplementsCommonWebDelegateSelectors() {
        // Arrange
        let manager = SheetNavigationManager(scriptSource: "")
        let item = DrawerItem(url: URL(string: "https://example.com")!)
        let runtime = DrawerPreviewRuntime(
            item: item,
            websiteDataStore: .nonPersistent(),
            sheetNavigation: manager,
            sheetScale: 100,
            onKeepInDrawer: { _ in },
            onKeepInDrawerInBackground: { _ in },
            onDiscard: {},
            onChange: { _, _, _ in },
            onDownloadFinished: { _ in },
            onDownloadFailed: { _ in }
        )
        defer { runtime.dispose() }

        let selectors = [
            "webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
            "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:",
            "webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:",
            "download:decideDestinationUsingResponse:suggestedFilename:completionHandler:",
            "downloadDidFinish:",
            "download:didFailWithError:resumeData:",
        ]

        // Assert
        #expect(selectors.allSatisfy { runtime.responds(to: NSSelectorFromString($0)) })
    }

    @Test func auxiliaryWebViewConfiguresBothUIDelegateAndNavigationDelegate() {
        // Arrange
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
        defer { runtime.dispose() }

        // Act
        let auxiliary = runtime.makeAuxiliaryWebView(
            configuration: WKWebViewConfiguration(),
            sourceWebView: runtime.webView
        )

        // Assert
        #expect(auxiliary.uiDelegate === runtime)
        #expect(auxiliary.navigationDelegate === runtime)
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
