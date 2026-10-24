import DenApplication
import Testing

nonisolated struct ZmxSessionNameGeneratorTests {
    @Test func zmxSessionNameGeneratorUsesRootAndSkipsCollisions() {
        let occupied: Set<String> = ["den", "den-vi", "den-vi-2", "den-2"]

        #expect(ZmxSessionNameGenerator.normalizedSuffix(" vi/nvim!? ") == "vinvim")
        #expect(
            ZmxSessionNameGenerator.nextName(
                rootSessionName: "den",
                suffix: "vi",
                occupiedNames: occupied)
                == "den-vi-3")
        #expect(
            ZmxSessionNameGenerator.nextName(
                rootSessionName: "den",
                suffix: "",
                occupiedNames: occupied)
                == "den-3")
    }
}
