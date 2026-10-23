import AppKit
import DenApplication
import DenDomain
import DenModels
import Testing

@testable import Den_Browser

@MainActor
struct WebBoardPointerFocusTests {
    @Test(arguments: [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown])
    func pressingUnfocusedSheetDoesNotChangeFocusedBoard(eventType: NSEvent.EventType) throws {
        // Arrange
        let current = BoardState(label: "Current", width: 520, currentSheetURL: nil)
        let target = BoardState(label: "Target", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [current, target], focusedBoardID: current.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let session = denWindowSession

            let webView = session.runtimes.webRuntime(for: target).webView
            let event = try #require(
                NSEvent.mouseEvent(
                    with: eventType,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1.0))

            // Act
            switch eventType {
            case .leftMouseDown: webView.mouseDown(with: event)
            case .rightMouseDown: webView.rightMouseDown(with: event)
            default: webView.otherMouseDown(with: event)
            }

            // Assert
            #expect(session.navigation.focusedBoard?.id == current.id)
        }
    }
}
