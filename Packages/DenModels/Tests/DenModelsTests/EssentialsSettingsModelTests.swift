import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct EssentialsSettingsModelTests {
    @Test func editsRevalidateCurrentIdentityAndKeyBeforePersisting() {
        let existing = Essential(name: "Existing", key: "e", input: "https://existing.example/")
        var items = [existing]
        var writes = 0
        var succeeds = true
        let model = EssentialsSettingsModel(
            read: { items },
            persist: {
                writes += 1
                if succeeds { items = $0 }
                return succeeds
            })

        #expect(model.save(id: nil, name: "Duplicate", key: "e", input: "https://other.example/") != nil)
        #expect(model.save(id: UUID(), name: "Missing", key: "m", input: "https://other.example/") != nil)
        #expect(writes == 0)
        #expect(model.save(id: existing.id, name: "Edited", key: "E", input: "https://edited.example/") == nil)
        #expect(model.essentials.first?.id == existing.id)
        #expect(model.essentials.first?.key == "E")
        succeeds = false
        #expect(model.delete(existing) != nil)
        #expect(model.essentials.count == 1)
        succeeds = true
        #expect(model.delete(existing) == nil)
        #expect(model.essentials.isEmpty)
    }
}
