import AppKit
import Combine
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct SheetURLPolicyTests {
    @Test func boardRuntimeLoadsLocalHTMLAndSiblingScript() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "DenBrowserFileURLTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let htmlURL = directory.appending(path: "index.html")
        let scriptURL = directory.appending(path: "title.js")
        try "<html><head><script src=\"title.js\"></script></head></html>".write(
            to: htmlURL,
            atomically: true,
            encoding: .utf8
        )
        try "document.title = 'Sibling script loaded';".write(
            to: scriptURL,
            atomically: true,
            encoding: .utf8
        )

        var continuation: AsyncStream<(URL?, String?)>.Continuation?
        let changes = AsyncStream<(URL?, String?)> { continuation = $0 }
        let runtime = WebRuntime(
            board: BoardState(label: "Local", width: 520, currentSheetURL: htmlURL),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            sheetScale: AppPreferences.defaultSheetScale,
            sheetNavigationActions: makeNoOpSheetNavigationActions(),
            events: boardRuntimeEvents { _, url, title in
                continuation?.yield((url, title))
            }
        )
        defer {
            continuation?.finish()
            runtime.dispose()
        }

        let observed = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await change in changes where change.1 == "Sibling script loaded" {
                    return true
                }
                return false
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                return false
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        #expect(observed)
    }

    @Test func boardRuntimeAppliesSafariUserAgent() {
        let userAgent = WebRuntime.defaultUserAgent
        #expect(userAgent.contains("Version/"))
        #expect(userAgent.contains("Safari/"))
    }

    @Test func sheetNavigationPreferencesPersist() {
        let suiteName = "SheetNavigationManagerTests-\(UUID().uuidString)"
        let defaults = makeTestDefaults(suiteName: suiteName)

        let manager = SheetNavigationManager(defaults: defaults, scriptSource: "")
        #expect(!manager.isEnabled)
        #expect(manager.hintAlphabet == "asdfghjkl")
        #expect(manager.userContentController.userScripts[0].source.contains("\"enabled\":false"))
        #expect(manager.userContentController.userScripts[0].source.contains("\"reduceMotion\":false"))

        manager.setReduceMotion(true)
        #expect(manager.userContentController.userScripts[0].source.contains("\"reduceMotion\":true"))

        manager.setEnabled(true)
        #expect(manager.setHintAlphabet("Aa1a"))
        #expect(manager.setIgnoredSites("Example.com\nhttps://www.apple.com/path\nexample.com"))
        #expect(manager.userContentController.userScripts[0].source.contains("\"enabled\":true"))
        #expect(manager.userContentController.userScripts[0].source.contains("\"alphabet\":\"a1\""))
        #expect(manager.ignoredHosts == ["example.com", "www.apple.com"])
        #expect(
            Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys) == [
                "preferences.sheet-navigation.enabled",
                "preferences.sheet-navigation.hint-alphabet",
                "preferences.sheet-navigation.ignored-hosts",
            ]
        )

        let restored = SheetNavigationManager(defaults: defaults, scriptSource: "")
        #expect(restored.isEnabled)
        #expect(restored.hintAlphabet == "a1")
        #expect(restored.ignoredHosts == ["example.com", "www.apple.com"])
    }

    @Test func pauseConfigurationRemainsAfterDocumentReload() async throws {
        let source = try makeSheetNavigationScriptSource().replacingOccurrences(
            of: "if (!event.isTrusted ||",
            with: "if ("
        )
        let suiteName = "SheetNavigationPauseConfigurationTests-\(UUID().uuidString)"
        let defaults = makeTestDefaults(suiteName: suiteName)
        let manager = SheetNavigationManager(defaults: defaults, scriptSource: source)
        let boardID = BoardID()
        let webView = makeSheetNavigationWebView(manager: manager)
        let waiter = WebViewLoadWaiter()
        let baseURL = URL(string: "https://example.com/")!

        manager.setEnabled(true)
        manager.didOpen(webView, boardID: boardID, actions: makeNoOpSheetNavigationActions())
        await waiter.load(sheetNavigationTestHTML, baseURL: baseURL, in: webView)

        manager.setBoardPaused(true, for: boardID)

        await waiter.load(sheetNavigationTestHTML, baseURL: baseURL, in: webView)
        manager.refreshConfiguration(for: webView)
        try await dispatchSheetKey("j", in: webView)

        let pausedScrollY = try #require(await webView.evaluateJavaScript("scrollY") as? Int)
        #expect(pausedScrollY == 0)

        manager.setBoardPaused(false, for: boardID)
        _ = try await webView.evaluateJavaScript("scrollTo(0, 0)")
        manager.refreshConfiguration(for: webView)
        try await dispatchSheetKey("j", in: webView)
        try await SheetInteraction.waitForFunction(expression: "scrollY > 0", in: webView)

        let resumedScrollY = try #require(await webView.evaluateJavaScript("scrollY") as? Int)
        #expect(resumedScrollY > 0)
    }

    @Test func invalidHintAlphabetIsNotPersisted() {
        let suiteName = "SheetNavigationAlphabetTests-\(UUID().uuidString)"
        let defaults = makeTestDefaults(suiteName: suiteName)
        let manager = SheetNavigationManager(defaults: defaults, scriptSource: "")

        #expect(!manager.setHintAlphabet("a"))
        #expect(!manager.setHintAlphabet("ab!"))
        #expect(!manager.setHintAlphabet("あい"))
        #expect(manager.hintAlphabet == "asdfghjkl")
    }

    @Test func invalidIgnoredSiteIsNotPersisted() {
        let suiteName = "SheetNavigationIgnoredSitesTests-\(UUID().uuidString)"
        let defaults = makeTestDefaults(suiteName: suiteName)
        let manager = SheetNavigationManager(defaults: defaults, scriptSource: "")

        #expect(!manager.setIgnoredSites("https://"))
        #expect(!manager.setIgnoredSites("not a host"))
        #expect(manager.ignoredHosts.isEmpty)
        #expect(manager.setIgnoredSites(""))
    }
}
