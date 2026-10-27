import AppKit
import Carbon
import DenDomain
import DenInfrastructure
import Observation

@MainActor
@Observable
final class BoardInputSourceTracker {
    private(set) var lastInputSourceByBoardID: [BoardID: String] = [:]
    private(set) var currentBoardID: BoardID?
    @ObservationIgnored private var notificationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var appActiveObserver: (any NSObjectProtocol)?
    var isEnabled: () -> Bool = { false }
    var canRecordInputSource: () -> Bool = {
        !(NSApp.keyWindow?.firstResponder is NSTextView)
    }

    init() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleKeyboardSelectionChanged()
            }
        }

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleApplicationDidBecomeActive()
            }
        }
    }

    isolated deinit {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }
    }

    func boardDidFocus(_ boardID: BoardID, isEnabled: Bool) {
        guard isEnabled else {
            currentBoardID = boardID
            return
        }

        if let currentBoardID, currentBoardID != boardID, let currentSource = currentInputSourceID() {
            lastInputSourceByBoardID[currentBoardID] = currentSource
        }
        currentBoardID = boardID

        if let savedSource = lastInputSourceByBoardID[boardID] {
            selectInputSource(id: savedSource)
        } else if let currentSource = currentInputSourceID() {
            lastInputSourceByBoardID[boardID] = currentSource
        }
    }

    func boardWillRemove(_ boardID: BoardID) {
        lastInputSourceByBoardID.removeValue(forKey: boardID)
        if currentBoardID == boardID {
            currentBoardID = nil
        }
    }

    private func handleKeyboardSelectionChanged() {
        guard isEnabled() else { return }
        guard canRecordInputSource() else { return }
        guard let currentBoardID, let currentSource = currentInputSourceID() else { return }
        lastInputSourceByBoardID[currentBoardID] = currentSource
    }

    private func handleApplicationDidBecomeActive() {
        guard isEnabled() else { return }
        guard let currentBoardID, let savedSource = lastInputSourceByBoardID[currentBoardID] else { return }
        selectInputSource(id: savedSource)
    }

    // MARK: - Carbon TIS Helpers

    func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    func selectInputSource(id: String) {
        let tracing = PerformanceTrace.isEnabled
        let startedAt = tracing ? ContinuousClock.now : nil
        let previousSource = currentInputSourceID()
        let match = previousSource.map { $0 == id ? "same" : "different" } ?? "unknown"
        let interval = PerformanceTrace.beginInterval("BoardInputSourceTracker.selectInputSource")
        var contextMilliseconds: Double?
        var contextLookupMilliseconds: Double?
        var contextSelectMilliseconds: Double?
        var carbonMilliseconds: Double?
        defer {
            let milliseconds = startedAt.map { $0.duration(to: .now) / .milliseconds(1) }
            PerformanceTrace.endInterval("BoardInputSourceTracker.selectInputSource", interval)
            if let milliseconds {
                let context = contextMilliseconds.map { String(format: "%.3f", $0) } ?? "none"
                let carbon = carbonMilliseconds.map { String(format: "%.3f", $0) } ?? "none"
                let lookup = contextLookupMilliseconds.map { String(format: "%.3f", $0) } ?? "none"
                let select = contextSelectMilliseconds.map { String(format: "%.3f", $0) } ?? "none"
                PerformanceTrace.mark(
                    String(
                        format: "match=%@ duration=%.3f context=%@ carbon=%@ contextLookup=%@ contextSelect=%@",
                        match, milliseconds, context, carbon, lookup, select),
                    category: "InputSource")
            }
        }
        guard previousSource != id else { return }
        let contextStartedAt = tracing ? ContinuousClock.now : nil
        let inputContext = NSTextInputContext.current
        if let contextStartedAt {
            contextLookupMilliseconds = contextStartedAt.duration(to: .now) / .milliseconds(1)
        }
        if let inputContext {
            let selectStartedAt = tracing ? ContinuousClock.now : nil
            inputContext.selectedKeyboardInputSource = id
            if let selectStartedAt {
                contextSelectMilliseconds = selectStartedAt.duration(to: .now) / .milliseconds(1)
            }
        }
        if let contextStartedAt {
            contextMilliseconds = contextStartedAt.duration(to: .now) / .milliseconds(1)
        }
        guard let current = currentInputSourceID(), current != id else { return }
        let properties = [kTISPropertyInputSourceID: id as CFString] as CFDictionary
        guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
            let target = list.first
        else {
            return
        }
        let carbonStartedAt = tracing ? ContinuousClock.now : nil
        TISSelectInputSource(target)
        if let carbonStartedAt {
            carbonMilliseconds = carbonStartedAt.duration(to: .now) / .milliseconds(1)
        }
    }

    func lastInputSource(for boardID: BoardID) -> String? {
        lastInputSourceByBoardID[boardID]
    }

    func setLastInputSource(_ id: String, for boardID: BoardID) {
        lastInputSourceByBoardID[boardID] = id
    }

    @ObservationIgnored private var labelCache: [String: String] = [:]

    static func resolveShortLabel(for inputSourceID: String) -> String {
        let properties = [kTISPropertyInputSourceID: inputSourceID as CFString] as CFDictionary
        if let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
            let source = list.first
        {
            // 1. Official macOS ASCII capability check (alphanumeric / half-width mode)
            if let asciiPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable),
                Unmanaged<CFBoolean>.fromOpaque(asciiPtr).takeUnretainedValue() == kCFBooleanTrue
            {
                return "A"
            }

            // 2. Language matching
            if let langPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
                let langs = Unmanaged<CFArray>.fromOpaque(langPtr).takeUnretainedValue() as? [String]
            {
                if langs.contains("ja") { return "あ" }
                if langs.contains("ko") { return "한" }
                if langs.contains("zh") { return "中" }
            }
        }

        // Fallback matching
        let lower = inputSourceID.lowercased()
        if lower.contains("roman") || lower.contains("abc") || lower.contains(".us") || lower.contains("ascii") {
            return "A"
        }
        if lower.contains("japanese") || lower.contains("kotoeri") {
            return "あ"
        }
        if lower.contains("korean") { return "한" }
        if lower.contains("chinese") || lower.contains("pinyin") { return "中" }
        return "A"
    }

    func shortLabel(for boardID: BoardID) -> String? {
        guard let id = lastInputSourceByBoardID[boardID] else { return nil }
        if let cached = labelCache[id] {
            return cached
        }
        let resolved = Self.resolveShortLabel(for: id)
        labelCache[id] = resolved
        return resolved
    }
}
