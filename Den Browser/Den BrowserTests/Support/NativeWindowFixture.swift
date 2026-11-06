import DenModels
import Foundation

@testable import Den_Browser

@MainActor
func withTestSession(
    resources: DenProfileResources,
    terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner(),
    _ body: (ProfileWindowSession) throws -> Void
) rethrows {
    let suiteName = "NativeWindowFixture-\(UUID().uuidString)"
    let defaults = makeTestDefaults(suiteName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let session = ProfileWindowSession(
        resources: resources,
        configuration: makeTestBoardRuntimeConfiguration(
            defaults: defaults, terminalCommandRunner: terminalCommandRunner))
    try body(session)
}

@MainActor
func withTestSession(
    resources: DenProfileResources,
    terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner(),
    _ body: @MainActor (ProfileWindowSession) async throws -> Void
) async rethrows {
    let suiteName = "NativeWindowFixture-\(UUID().uuidString)"
    let defaults = makeTestDefaults(suiteName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let session = ProfileWindowSession(
        resources: resources,
        configuration: makeTestBoardRuntimeConfiguration(
            defaults: defaults, terminalCommandRunner: terminalCommandRunner))
    try await body(session)
}

@MainActor
func withTestWindow(
    resources: DenProfileResources,
    terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner(),
    _ body: (ProfileWindowSession, DenWindowModel) throws -> Void
) rethrows {
    try withTestSession(resources: resources, terminalCommandRunner: terminalCommandRunner) { session in
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        try body(session, composition.model)
    }
}

@MainActor
func withTestWindow(
    resources: DenProfileResources,
    terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner(),
    _ body: @MainActor (ProfileWindowSession, DenWindowModel) async throws -> Void
) async rethrows {
    try await withTestSession(resources: resources, terminalCommandRunner: terminalCommandRunner) { session in
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        try await body(session, composition.model)
    }
}
