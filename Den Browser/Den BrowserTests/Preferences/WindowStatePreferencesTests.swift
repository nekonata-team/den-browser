import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct WindowStatePreferencesTests {
    @Test func cleanupPersistsWhenLegacyKeyNamesExceedFourMiB() throws {
        // Arrange
        let suiteName = "WindowStatePreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let legacyKeys = (0..<2).map { index in
            "NSWindow Frame SwiftUI.WindowGroup<Den_Browser.ProfileWindowView,"
                + String(repeating: "x", count: 2 * 1024 * 1024) + "\(index)>"
        }
        defer {
            for key in legacyKeys { defaults.removeObject(forKey: key) }
            defaults.removeObject(forKey: "preferences.search.engine")
            defaults.synchronize()
        }
        defaults.set("google", forKey: "preferences.search.engine")
        for key in legacyKeys { defaults.set("frame", forKey: key) }
        try #require(defaults.synchronize())
        try #require(try readSavedDomain(suiteName).count == 3)

        // Act
        WindowStatePreferences.removeLegacyProfileState(defaults: defaults, domainName: suiteName)
        try #require(defaults.synchronize())

        // Assert
        let saved = try readSavedDomain(suiteName)
        #expect(saved.count == 1)
        #expect(saved["preferences.search.engine"] == "google")
    }

    // A separate process observes durable state, rather than UserDefaults' in-process cache.
    private func readSavedDomain(_ suiteName: String) throws -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", suiteName, "-"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    @Test func removesOnlyLegacyProfileWindowState() throws {
        // Arrange
        let suiteName = "WindowStatePreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let retained: [String: String] = [
            "preferences.search.engine": "google",
            "NSWindow Frame profile-window-AppWindow-1": "frame",
            "NSSplitView Subview Frames profile-window-AppWindow-1, SidebarNavigationSplitView": "split",
            "NSWindow Frame SwiftUI.WindowGroup<OtherView>": "other-window",
            "NSSplitView Subview Frames SwiftUI.WindowGroup<OtherView>": "other-split",
            "unrelated.ProfileWindowView,": "unrelated",
        ]
        var domain = retained
        for type in ["WindowGroup", "PresentedWindowContent"] {
            let identifier = "SwiftUI.\(type)<Den_Browser.ProfileWindowView, Modifier>-1-AppWindow-1"
            domain["NSWindow Frame \(identifier)"] = "legacy-frame"
            domain["NSSplitView Subview Frames \(identifier), SidebarNavigationSplitView"] = "legacy-split"
        }
        defaults.setPersistentDomain(domain, forName: suiteName)

        // Act
        WindowStatePreferences.removeLegacyProfileState(defaults: defaults, domainName: suiteName)
        WindowStatePreferences.removeLegacyProfileState(defaults: defaults, domainName: suiteName)

        // Assert
        #expect(defaults.persistentDomain(forName: suiteName) as? [String: String] == retained)
    }
}
