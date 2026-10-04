import Foundation
import Testing

@testable import Den_Browser

struct DenIPCTransportTests {
    @Test func temporarySocketPathUsesPrefixAndIdentifier() {
        let temporaryDirectory = URL(fileURLWithPath: "/tmp/den-test")

        #expect(
            DenSocketPath.temporary(
                prefix: "den-test",
                identifier: "unit",
                temporaryDirectory: temporaryDirectory) == "/tmp/den-test/den-test-unit.sock")
    }

    @Test func socketPathResolutionUsesExplicitEnvironmentThenDefault() {
        let home = URL(fileURLWithPath: "/tmp/den-home")

        #expect(
            DenSocketPath.resolve(
                explicit: "/tmp/explicit.sock",
                environment: ["DEN_SOCKET": "/tmp/environment.sock"],
                homeDirectory: home) == "/tmp/explicit.sock")
        #expect(
            DenSocketPath.resolve(
                environment: ["DEN_SOCKET": "/tmp/environment.sock"],
                homeDirectory: home) == "/tmp/environment.sock")
        #expect(
            DenSocketPath.resolve(environment: [:], homeDirectory: home) == "/tmp/den-home/.den/den.sock")
    }

    @Test func emptyEnvironmentSocketFallsBackToDefault() {
        let home = URL(fileURLWithPath: "/tmp/den-home")

        #expect(
            DenSocketPath.resolve(environment: ["DEN_SOCKET": ""], homeDirectory: home)
                == "/tmp/den-home/.den/den.sock")
    }
}
