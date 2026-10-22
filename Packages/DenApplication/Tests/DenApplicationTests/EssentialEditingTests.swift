import DenApplication
import DenDomain
import Testing

@MainActor
struct EssentialEditingTests {
    @Test func savingNormalizesSpaceKeyAndConfirmationRevalidatesCurrentIdentity() {
        // Arrange
        var items: [Essential] = []
        let editing = EssentialEditing(
            read: { items },
            persist: {
                items = $0
                return true
            })
        // Act
        guard case .saved(let original) = editing.save(name: " Original ", key: " ", input: " example.com ") else {
            Issue.record("Valid Essential must save")
            return
        }
        guard
            case .confirmation(let existing, let replacement) = editing.save(
                name: "Replacement", key: " ", input: "next.example")
        else {
            Issue.record("Duplicate key requires confirmation")
            return
        }
        items[0].key = "x"
        let result = editing.replace(replacement)
        // Assert
        #expect(original.name == "Original")
        #expect(original.key == " ")
        #expect(existing.id == replacement.id)
        #expect(items[0].name == original.name)
        guard case .missing = result else {
            Issue.record("Changed key must invalidate confirmation")
            return
        }
    }

    @Test func invalidInputAndFailedPersistenceDoNotReportSuccess() {
        // Arrange
        let original = Essential(name: "Original", key: "o", input: "example.com")
        var saves = 0
        let editing = EssentialEditing(
            read: { [original] },
            persist: { _ in
                saves += 1
                return false
            })
        // Act
        let invalid = editing.save(name: " ", key: "x", input: "example.com")
        let failed = editing.replace(original)
        // Assert
        guard case .invalid = invalid, case .persistenceFailed = failed else {
            Issue.record("Invalid and failed writes must remain distinct")
            return
        }
        #expect(saves == 1)
    }
}
