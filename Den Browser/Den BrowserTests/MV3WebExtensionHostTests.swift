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

    @Test func descriptorSupportsDirectoryURL() {
        let tempDir = FileManager.default.temporaryDirectory
        let descriptor = WebExtensionDescriptor(
            identifier: "custom.extension",
            directoryURL: tempDir,
            preapproveRequestedAccess: true)

        #expect(descriptor.identifier == "custom.extension")
        #expect(descriptor.directoryURL == tempDir)
        #expect(descriptor.preapproveRequestedAccess)
        #expect(descriptor.resourceURL() == tempDir)
    }

    @Test func uboliteInstallerTracksInstallationState() {
        let nonExistentDir = FileManager.default.temporaryDirectory
            .appending(path: "test-non-existent-\(UUID().uuidString)")
        let installer = UBOLiteInstaller(directoryURL: nonExistentDir)

        #expect(!installer.isInstalled)
        #expect(installer.installedVersion == nil)
        #expect(installer.descriptor == nil)
    }

    @Test func uboliteInstallerReadsInstalledVersionFromManifest() {
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/MV3Extension", directoryHint: .isDirectory)
        let installer = UBOLiteInstaller(directoryURL: fixtureDir)

        #expect(installer.isInstalled)
        #expect(installer.installedVersion == "1.0.0")
        #expect(installer.descriptor != nil)
    }
}
