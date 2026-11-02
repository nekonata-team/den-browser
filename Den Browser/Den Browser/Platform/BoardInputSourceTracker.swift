import AppKit
import Carbon
import DenDomain
import DenInfrastructure
import DenModels
import Observation

@MainActor
@Observable
final class BoardInputSourceTracker {
    private(set) var lastInputSourceByBoardID: [BoardID: String] = [:]
    private(set) var currentBoardID: BoardID?
    @ObservationIgnored private var notificationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var appActiveObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var windowActiveObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSource: String?
    @ObservationIgnored private var sourceBeforeRestore: String?
    @ObservationIgnored var isHandlingKeyboardAction = false
    @ObservationIgnored var isDenMode: () -> Bool = { false }
    @ObservationIgnored var canRestoreInputSource: () -> Bool = { NSApp.isActive }
    @ObservationIgnored var readInputSource: @MainActor () -> String? = systemCurrentInputSourceID
    @ObservationIgnored var restoreInputSource: @MainActor (String) -> Void = systemSelectInputSource
    var isEnabled: () -> Bool = { false }
    var canRecordInputSource: () -> Bool = {
        !(NSApp.keyWindow?.firstResponder is NSTextView)
    }

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        notificationObserver = notificationCenter.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleKeyboardSelectionChanged()
            }
        }

        appActiveObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleApplicationDidBecomeActive()
            }
        }
        windowActiveObserver = notificationCenter.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleApplicationDidBecomeActive()
            }
        }
    }

    isolated deinit {
        restoreTask?.cancel()
        if let notificationObserver {
            notificationCenter.removeObserver(notificationObserver)
        }
        if let appActiveObserver {
            notificationCenter.removeObserver(appActiveObserver)
        }
        if let windowActiveObserver {
            notificationCenter.removeObserver(windowActiveObserver)
        }
    }

    func boardDidFocus(_ boardID: BoardID, isEnabled: Bool) {
        guard isEnabled else {
            cancelPendingRestoration()
            currentBoardID = boardID
            return
        }
        if currentBoardID == boardID, pendingSource != nil { return }

        let currentSource = readInputSource()
        // A Board passed during navigation has not used its saved input source yet.
        if pendingSource == nil, let currentBoardID, currentBoardID != boardID, let currentSource {
            lastInputSourceByBoardID[currentBoardID] = currentSource
        }
        cancelPendingRestoration()
        currentBoardID = boardID

        if let savedSource = lastInputSourceByBoardID[boardID], savedSource != currentSource {
            pendingSource = savedSource
            sourceBeforeRestore = currentSource
            if !isDenMode() {
                if isHandlingKeyboardAction {
                    scheduleRestoration()
                } else {
                    restorePendingInputSource()
                }
            }
        } else if let currentSource {
            lastInputSourceByBoardID[boardID] = currentSource
        }
    }

    private func scheduleRestoration() {
        restoreTask?.cancel()
        // Keep the navigation delay even when spatial animation is disabled.
        let deadline = ContinuousClock.now.advanced(by: .seconds(MotionPreference.standardSpatialDuration))
        restoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled, let self, !isDenMode(), canRestoreInputSource(), canRecordInputSource() else {
                return
            }
            restorePendingInputSource()
        }
    }

    func denModeDidChange() {
        if isDenMode() {
            restoreTask?.cancel()
        } else {
            restorePendingInputSource()
        }
    }

    func restorePendingInputSource() {
        let source = pendingSource
        cancelPendingRestoration()
        guard isEnabled(), let source else { return }
        restoreInputSource(source)
    }

    func cancelPendingRestoration() {
        restoreTask?.cancel()
        restoreTask = nil
        pendingSource = nil
        sourceBeforeRestore = nil
    }

    func boardWillRemove(_ boardID: BoardID) {
        lastInputSourceByBoardID.removeValue(forKey: boardID)
        if currentBoardID == boardID {
            cancelPendingRestoration()
            currentBoardID = nil
        }
    }

    private func handleKeyboardSelectionChanged() {
        guard isEnabled(), canRestoreInputSource() else { return }
        guard canRecordInputSource() else { return }
        guard let currentBoardID, let currentSource = readInputSource() else { return }
        if pendingSource != nil {
            guard currentSource != sourceBeforeRestore else { return }
            cancelPendingRestoration()
        }
        lastInputSourceByBoardID[currentBoardID] = currentSource
    }

    private func handleApplicationDidBecomeActive() {
        guard isEnabled(), canRestoreInputSource(), canRecordInputSource(), !isDenMode() else { return }
        guard let currentBoardID, let savedSource = lastInputSourceByBoardID[currentBoardID] else { return }
        cancelPendingRestoration()
        restoreInputSource(savedSource)
    }

    // MARK: - Carbon TIS Helpers

    private static func systemCurrentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static func systemSelectInputSource(id: String) {
        let tracing = PerformanceTrace.isEnabled
        let startedAt = tracing ? ContinuousClock.now : nil
        let previousSource = systemCurrentInputSourceID()
        let match = previousSource.map { $0 == id ? "same" : "different" } ?? "unknown"
        let interval = PerformanceTrace.beginInterval("BoardInputSourceTracker.selectInputSource")
        var carbonMilliseconds: Double?
        var carbonStatus: OSStatus?
        var restored: Bool?
        defer {
            let milliseconds = startedAt.map { $0.duration(to: .now) / .milliseconds(1) }
            PerformanceTrace.endInterval("BoardInputSourceTracker.selectInputSource", interval)
            if let milliseconds {
                let carbon = carbonMilliseconds.map { String(format: "%.3f", $0) } ?? "none"
                let status = carbonStatus.map { String($0) } ?? "none"
                let didRestore = restored.map { String($0) } ?? "none"
                PerformanceTrace.mark(
                    String(
                        format:
                            "match=%@ duration=%.3f context=none carbon=%@ contextLookup=none contextSelect=none status=%@ restored=%@",
                        match, milliseconds, carbon, status, didRestore),
                    category: "InputSource")
            }
        }
        guard previousSource != id else { return }
        let properties = [kTISPropertyInputSourceID: id as CFString] as CFDictionary
        guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
            let target = list.first
        else {
            return
        }
        let carbonStartedAt = tracing ? ContinuousClock.now : nil
        carbonStatus = TISSelectInputSource(target)
        if let carbonStartedAt {
            carbonMilliseconds = carbonStartedAt.duration(to: .now) / .milliseconds(1)
            restored = systemCurrentInputSourceID() == id
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
