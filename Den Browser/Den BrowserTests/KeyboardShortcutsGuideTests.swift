import Testing

@testable import Den_Browser

@MainActor
struct KeyboardShortcutsGuideTests {
    @Test func searchMatchesActionKeysAndCategory() {
        // Arrange
        let section = ShortcutGuideSection(
            title: "Board Actions",
            items: [
                ShortcutGuideItem(keys: ["⌘", "T"], label: "Open Board", accessibilityKeys: "Command T"),
                ShortcutGuideItem(keys: ["f"], label: "Toggle maximized Board", accessibilityKeys: "f"),
            ])

        // Act
        let actionMatch = section.filtered(matching: "open board")
        let keyMatch = section.filtered(matching: "⌘ T")
        let categoryMatch = section.filtered(matching: "board actions")
        let missingMatch = section.filtered(matching: "unknown")

        // Assert
        #expect(actionMatch?.items.map(\.label) == ["Open Board"])
        #expect(keyMatch?.items.map(\.label) == ["Open Board"])
        #expect(categoryMatch?.items.count == 2)
        #expect(missingMatch == nil)
    }
}
