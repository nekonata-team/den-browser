import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct TerminalURLSuppressionTrackerTests {
    @Test func suppressesRegisteredURLWithinWindow() {
        var tracker = TerminalURLSuppressionTracker()
        let url = URL(string: "https://example.com/page")!
        let now = Date()

        tracker.register(url, now: now)
        let firstConsumed = tracker.consume(url, now: now.addingTimeInterval(0.5))
        #expect(firstConsumed)

        let secondConsumed = tracker.consume(url, now: now.addingTimeInterval(0.6))
        #expect(!secondConsumed)
    }

    @Test func expiresSuppressionAfterWindow() {
        var tracker = TerminalURLSuppressionTracker()
        let url = URL(string: "https://example.com/page")!
        let now = Date()

        tracker.register(url, now: now)
        let consumed = tracker.consume(url, now: now.addingTimeInterval(1.5))
        #expect(!consumed)
    }

    @Test func cancelsRegistration() {
        var tracker = TerminalURLSuppressionTracker()
        let url = URL(string: "https://example.com/page")!
        let now = Date()

        tracker.register(url, now: now)
        tracker.cancel(url, now: now.addingTimeInterval(0.1))
        let consumed = tracker.consume(url, now: now.addingTimeInterval(0.2))
        #expect(!consumed)
    }

    @Test func handlesMultipleRegistrationsForSameURL() {
        var tracker = TerminalURLSuppressionTracker()
        let url = URL(string: "https://example.com/page")!
        let now = Date()

        tracker.register(url, now: now)
        tracker.register(url, now: now.addingTimeInterval(0.2))

        let first = tracker.consume(url, now: now.addingTimeInterval(0.3))
        #expect(first)
        let second = tracker.consume(url, now: now.addingTimeInterval(0.4))
        #expect(second)
        let third = tracker.consume(url, now: now.addingTimeInterval(0.5))
        #expect(!third)
    }
}
