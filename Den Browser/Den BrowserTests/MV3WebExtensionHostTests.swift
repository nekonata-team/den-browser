import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct MV3WebExtensionHostTests {
    @Test func controllerConfigurationIsProfileScoped() {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let first = MV3WebExtensionHost(
            profileID: firstProfileID,
            websiteDataStore: .nonPersistent(),
            userContentController: WKUserContentController())
        let second = MV3WebExtensionHost(
            profileID: secondProfileID,
            websiteDataStore: .nonPersistent(),
            userContentController: WKUserContentController())

        #expect(first.controller !== second.controller)
        #expect(first.controller.configuration.identifier == firstProfileID)
        #expect(second.controller.configuration.identifier == secondProfileID)

        first.dispose()
        second.dispose()
    }

    @Test func registeringWebViewInAnotherWindowMovesItsTab() {
        let host = MV3WebExtensionHost(
            profileID: UUID(),
            websiteDataStore: .nonPersistent(),
            userContentController: WKUserContentController())
        let webView = WKWebView(frame: .zero)
        let firstWindow = host.window(for: UUID())
        let secondWindow = host.window(for: UUID())
        defer {
            host.unregister(webView: webView)
            host.dispose()
        }

        host.register(webView: webView, in: firstWindow, initialURL: nil) { _ in }
        #expect(firstWindow.tabs.count == 1)
        host.register(webView: webView, in: firstWindow, initialURL: nil) { _ in }
        #expect(firstWindow.tabs.count == 1)

        host.register(webView: webView, in: secondWindow, initialURL: nil) { _ in }
        #expect(firstWindow.tabs.isEmpty)
        #expect(secondWindow.tabs.count == 1)
    }

    @Test func bundledDescriptorKeepsResourceLookupExplicit() {
        let descriptor = BundledWebExtensionDescriptor(
            identifier: "example.extension",
            resourceName: "Extension",
            resourceSubdirectory: "Bundled")

        #expect(descriptor.identifier == "example.extension")
        #expect(descriptor.resourceName == "Extension")
        #expect(descriptor.resourceSubdirectory == "Bundled")
        #expect(!descriptor.preapproveRequestedAccess)
        #expect(descriptor.resourceURL(in: .main) == nil)
    }

    @Test func webKitParsesManifestV3Fixture() async throws {
        let resourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/MV3Extension", directoryHint: .isDirectory)
        let webExtension = try await WKWebExtension(resourceBaseURL: resourceURL)

        #expect(webExtension.manifestVersion == 3)
        #expect(webExtension.hasInjectedContent)
    }

    @Test func bundledUBOLReleaseIsManifestV3() async throws {
        let resourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(
                path: "Den Browser/Resources/WebExtensions/uBOLite.safari.zip",
                directoryHint: .notDirectory)
        let webExtension = try await WKWebExtension(resourceBaseURL: resourceURL)

        #expect(webExtension.manifestVersion == 3)
        #expect(webExtension.hasBackgroundContent)
        #expect(webExtension.hasContentModificationRules)
        #expect(!webExtension.hasInjectedContent)

        let configuration = WKWebExtensionController.Configuration(identifier: UUID())
        configuration.defaultWebsiteDataStore = .nonPersistent()
        let controller = WKWebExtensionController(configuration: configuration)
        let context = WKWebExtensionContext(for: webExtension)
        context.unsupportedAPIs = ["browser.storage.sync"]
        let expirationDate = Date.distantFuture
        context.grantedPermissions = Dictionary(
            uniqueKeysWithValues: webExtension.requestedPermissions.map { ($0, expirationDate) })
        context.grantedPermissionMatchPatterns = Dictionary(
            uniqueKeysWithValues: webExtension.requestedPermissionMatchPatterns.map { ($0, expirationDate) })

        try controller.load(context)
        #expect(context.errors.isEmpty)
        #expect(context.action(for: nil) != nil)
        #expect(context.optionsPageURL != nil)
        try controller.unload(context)
    }
}
