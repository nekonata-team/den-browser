import Foundation

@MainActor
struct TerminalURLSuppressionTracker {
    // ponytail: one-second handoff window; replace with source-aware URL routing if available.
    static let duration: TimeInterval = 1
    private var pending: [URL: (count: Int, expiresAt: Date)] = [:]

    mutating func register(_ url: URL, now: Date = Date()) {
        let canonical = SheetURLPolicy.canonicalSheetURL(url)
        let expiration = now.addingTimeInterval(Self.duration)
        if let current = pending[canonical], current.expiresAt > now {
            pending[canonical] = (current.count + 1, expiration)
        } else {
            pending[canonical] = (1, expiration)
        }
    }

    mutating func cancel(_ url: URL, now: Date = Date()) {
        _ = consume(url, now: now)
    }

    mutating func consume(_ url: URL, now: Date = Date()) -> Bool {
        let canonical = SheetURLPolicy.canonicalSheetURL(url)
        guard let current = pending[canonical] else { return false }
        guard current.expiresAt > now else {
            pending.removeValue(forKey: canonical)
            return false
        }
        if current.count == 1 {
            pending.removeValue(forKey: canonical)
        } else {
            pending[canonical] = (current.count - 1, current.expiresAt)
        }
        return true
    }
}
