import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct AppPreferencesTests {

    @Test func automaticPictureInPictureDefaultsToDisabled() throws {
        // Arrange
        let suiteName = "AutomaticPictureInPictureDefaultsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Act
        let preferences = AppPreferences(defaults: defaults)

        // Assert
        #expect(!preferences.automaticPIPOnDeskSwitch)
    }

    @Test func searchEngineDefaultsToGoogle() throws {
        // Arrange
        let suiteName = "SearchEngineDefaultsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Act
        let preferences = AppPreferences(defaults: defaults)

        // Assert
        #expect(preferences.searchEngine == .google)
    }

    @Test func searchEnginePreferencePersistsCustomEngine() throws {
        // Arrange
        let suiteName = "SearchEnginePersistTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)

        for engine in SearchEngine.allCases {
            // Act
            preferences.setSearchEngine(engine)

            // Assert
            #expect(AppPreferences(defaults: defaults).searchEngine == engine)
        }
    }

    @Test func searchEnginePreferenceFallsBackToGoogleForUnknownValue() throws {
        // Arrange
        let suiteName = "SearchEngineFallbackTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unknown", forKey: "preferences.search.engine")

        // Act
        let preferences = AppPreferences(defaults: defaults)

        // Assert
        #expect(preferences.searchEngine == .google)
    }

    @Test func appPreferencesClampSheetScale() throws {
        // Arrange
        let suiteName = "AppPreferencesClampTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)

        // Act
        preferences.setSheetScale(49)
        preferences.setSheetScale(201)

        // Assert
        #expect(preferences.sheetScale == AppPreferences.defaultSheetScale)
    }

    @Test func appPreferencesPersistByKey() throws {
        // Arrange
        let suiteName = "AppPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)

        // Act
        preferences.setMotionPreference(.standard)
        preferences.setUBOLiteEnabled(true)
        preferences.setExternalLinkDestination(.focusedBoard)
        preferences.setAutomaticPIPOnDeskSwitch(true)
        preferences.setSheetScale(80)
        preferences.setZellijPath(" /opt/homebrew/bin/zellij ")
        preferences.setZmxPath(" /opt/homebrew/bin/zmx ")

        // Assert
        let restored = AppPreferences(defaults: defaults)
        let storedKeys = Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys)
        #expect(
            storedKeys == [
                "preferences.schema.version",
                "preferences.appearance.motion.mode",
                "preferences.content-blocking.ubolite.enabled",
                "preferences.external-links.destination",
                "preferences.picture-in-picture.auto-on-desk-switch",
                "preferences.appearance.sheet-scale.percent",
                "preferences.terminal.zellij.executable-path",
                "preferences.terminal.zmx.executable-path",
            ])
        #expect(defaults.integer(forKey: "preferences.schema.version") == 1)
        #expect(restored.motionPreference == .standard)
        #expect(restored.uBOLiteEnabled)
        #expect(restored.externalLinkDestination == .focusedBoard)
        #expect(restored.automaticPIPOnDeskSwitch)
        #expect(restored.sheetScale == 80)
        #expect(restored.zellijPath == "/opt/homebrew/bin/zellij")
        #expect(restored.zmxPath == "/opt/homebrew/bin/zmx")
    }

    @Test func essentialsPersistWithoutProfileOwnership() throws {
        // Arrange
        let suiteName = "AppPreferencesEssentialsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let essentials = [
            Essential(name: "ChatGPT", key: "C", input: "https://chatgpt.com"),
            Essential(name: "Terminal", key: "T", input: ":terminal ~/Projects"),
        ]

        // Act
        let saved = preferences.setEssentials(essentials)

        // Assert
        #expect(saved)
        #expect(AppPreferences(defaults: defaults).essentials == essentials)
    }

    @Test func essentialsRejectDuplicateKey() throws {
        // Arrange
        let suiteName = "AppPreferencesDuplicateKeyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let essentials = [
            Essential(name: "ChatGPT", key: "C", input: "https://chatgpt.com"),
            Essential(name: "Duplicate", key: "C", input: "other"),
        ]

        // Act
        let saved = preferences.setEssentials(essentials)

        // Assert
        #expect(!saved)
    }

    @Test func essentialsAllowCaseSensitiveKeys() throws {
        // Arrange
        let suiteName = "AppPreferencesCaseKeyTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let essentials = [
            Essential(name: "Upper", key: "C", input: "first"),
            Essential(name: "Lower", key: "c", input: "second"),
        ]

        // Act
        let saved = preferences.setEssentials(essentials)

        // Assert
        #expect(saved)
        #expect(AppPreferences(defaults: defaults).essentials == essentials)
    }

    @Test func essentialsCanBeCleared() throws {
        // Arrange
        let suiteName = "AppPreferencesClearEssentialsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setEssentials([Essential(name: "ChatGPT", key: "C", input: "https://chatgpt.com")])

        // Act
        preferences.setEssentials([])

        // Assert
        #expect(AppPreferences(defaults: defaults).essentials.isEmpty)
    }

    @Test func appPreferencesInitializeMissingSchema() throws {
        // Arrange
        let suiteName = "AppPreferencesMissingSchemaTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Act
        let preferences = AppPreferences(defaults: defaults)

        // Assert
        #expect(defaults.integer(forKey: "preferences.schema.version") == 1)
        #expect(preferences.sheetScale == AppPreferences.defaultSheetScale)
    }

    @Test func appPreferencesDoNotDowngradeFutureSchema() throws {
        // Arrange
        let suiteName = "AppPreferencesFutureSchemaTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(2, forKey: "preferences.schema.version")

        // Act
        _ = AppPreferences(defaults: defaults)

        // Assert
        #expect(defaults.integer(forKey: "preferences.schema.version") == 2)
    }

    @Test func motionPreferenceFollowsOrOverridesSystemSetting() {
        // Arrange
        let testCases: [(preference: MotionPreference, systemReduce: Bool, expected: Bool)] = [
            (.followSystem, true, true),
            (.followSystem, false, false),
            (.standard, true, false),
            (.reduced, false, true),
        ]

        for testCase in testCases {
            // Act
            let shouldReduce = DenMotion.shouldReduceMotion(
                preference: testCase.preference,
                systemReduceMotion: testCase.systemReduce
            )

            // Assert
            #expect(shouldReduce == testCase.expected)
        }
    }

    @Test func drawerStylePersistsAndToggles() throws {
        let suiteName = "AppPreferencesDrawerTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)

        #expect(preferences.drawerStyle == .floating)

        preferences.toggleDrawerStyle()
        #expect(preferences.drawerStyle == .bottom)
        #expect(defaults.string(forKey: "preferences.drawer.style") == "bottom")

        let restored = AppPreferences(defaults: defaults)
        #expect(restored.drawerStyle == .bottom)

        restored.toggleDrawerStyle()
        #expect(restored.drawerStyle == .floating)
    }
}
