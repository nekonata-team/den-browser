import AppKit
import SwiftUI

struct ShortcutsSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var recordingAction: ShortcutAction?
    @State private var recordingDeskNumberShortcut = false
    @State private var recordingMonitor: Any?
    @State private var errorMessage: String?
    @State private var isGuidePresented = false

    var body: some View {
        Form {
            Section("Shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    shortcutRow(action)
                }
                deskNumberShortcutRow
            }

            Section {
                HStack {
                    Button("View All Shortcuts…") {
                        stopRecording()
                        isGuidePresented = true
                    }
                    Spacer()
                    Button("Reset All") {
                        stopRecording()
                        preferences.resetAllShortcuts()
                    }
                    .disabled(
                        preferences.shortcutOverrides.isEmpty
                            && !preferences.hasDeskNumberBindingOverride())
                }
            }

            Text("Custom shortcuts take priority over Sheet input while their Den window is active.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .onDisappear(perform: stopRecording)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stopRecording()
        }
        .sheet(isPresented: $isGuidePresented) {
            KeyboardShortcutsView { isGuidePresented = false }
                .padding(18)
                .frame(width: 760, height: 560)
        }
    }

    private var deskNumberShortcutRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("Focus Desk 1–10 (enter a digit, e.g. 1)")
                Spacer()

                Button {
                    if recordingDeskNumberShortcut {
                        stopRecording()
                    } else {
                        startRecordingDeskNumberShortcut()
                    }
                } label: {
                    ShortcutChip(
                        tokens: recordingDeskNumberShortcut
                            ? ["Type shortcut…"]
                            : preferences.deskNumberBinding?.displayTokens ?? ["Unassigned"],
                        width: 124,
                        isRecording: recordingDeskNumberShortcut)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    recordingDeskNumberShortcut
                        ? "Cancel recording for Focus Desk 1 through 10"
                        : "Record shortcut for Focus Desk 1 through 10, current shortcut \(preferences.deskNumberBinding?.accessibilityLabel ?? "unassigned")"
                )
                .help(recordingDeskNumberShortcut ? "Cancel recording" : "Record a new shortcut")

                Button {
                    stopRecording()
                    preferences.clearDeskNumberBinding()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.borderless)
                .disabled(preferences.deskNumberBinding == nil)
                .accessibilityLabel("Clear shortcut for Focus Desk 1 through 10")
                .help("Clear shortcut")

                Button {
                    stopRecording()
                    preferences.resetDeskNumberBinding()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.borderless)
                .disabled(!preferences.hasDeskNumberBindingOverride())
                .accessibilityLabel("Reset shortcut for Focus Desk 1 through 10")
                .help("Reset shortcut")
            }

            if recordingDeskNumberShortcut, let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(action.label)
                Spacer()

                Button {
                    if recordingAction == action {
                        stopRecording()
                    } else {
                        startRecording(action)
                    }
                } label: {
                    ShortcutChip(
                        tokens: bindingTokens(for: action),
                        width: 124,
                        isRecording: recordingAction == action
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bindingAccessibilityLabel(for: action))
                .help(recordingAction == action ? "Cancel recording" : "Record a new shortcut")

                if action.canBeUnassigned {
                    Button {
                        stopRecording()
                        preferences.clearShortcut(for: action)
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .disabled(preferences.shortcut(for: action) == nil)
                    .accessibilityLabel("Clear shortcut for \(action.label)")
                    .help("Clear shortcut")
                }

                Button {
                    stopRecording()
                    preferences.resetShortcut(for: action)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.borderless)
                .disabled(!preferences.hasShortcutOverride(for: action))
                .accessibilityLabel("Reset shortcut for \(action.label)")
                .help("Reset shortcut")
            }

            if recordingAction == action, let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if optionCharacterWarning(for: action) {
                Text("This shortcut may replace text input in Sheets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        errorMessage = nil
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            capture(event, for: action)
            return nil
        }
    }

    private func startRecordingDeskNumberShortcut() {
        stopRecording()
        recordingDeskNumberShortcut = true
        errorMessage = nil
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            captureDeskNumberShortcut(event)
            return nil
        }
    }

    private func capture(_ event: NSEvent, for action: ShortcutAction) {
        if event.keyCode == 53,
            event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        {
            stopRecording()
            return
        }

        guard let binding = ShortcutBinding(event: event), binding.isRecordable else {
            errorMessage = "Use Control, Option, or Command with a supported key."
            return
        }

        if let menuItem = conflictingMenuItem(for: binding) {
            errorMessage = "\(binding.displayName) is already used by \(menuItem.title)."
            return
        }

        if let error = preferences.setShortcut(binding, for: action) {
            switch error {
            case .invalid:
                errorMessage = "Use Control, Option, or Command with a supported key."
            case .conflict(let conflictingAction):
                errorMessage = "\(binding.displayName) is already assigned to \(conflictingAction.label)."
            case .conflictWithDeskNumber:
                errorMessage = "This shortcut is already used for Desk navigation."
            }
            return
        }

        stopRecording()
    }

    private func captureDeskNumberShortcut(_ event: NSEvent) {
        if event.keyCode == 53,
            event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        {
            stopRecording()
            return
        }

        guard let recordedBinding = ShortcutBinding(event: event),
            recordedBinding.key.deskNumber != nil
        else {
            errorMessage = "Type a digit with Control, Option, or Command."
            return
        }

        // The digit is selected at runtime; only its modifier combination is configurable.
        let binding = ShortcutBinding(key: .character("1"), modifiers: recordedBinding.modifiers)
        if let menuItem = conflictingMenuItem(for: binding) {
            errorMessage = "\(binding.displayName) is already used by \(menuItem.title)."
            return
        }

        if let error = preferences.setDeskNumberBinding(binding) {
            switch error {
            case .invalid:
                errorMessage = "Use Control, Option, or Command."
            case .conflict(let conflictingAction):
                errorMessage = "This shortcut conflicts with \(conflictingAction.label)."
            case .conflictWithDeskNumber:
                errorMessage = "This shortcut is already used for Desk navigation."
            }
            return
        }

        stopRecording()
    }

    private func stopRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
        recordingAction = nil
        recordingDeskNumberShortcut = false
        errorMessage = nil
    }

    private func conflictingMenuItem(for binding: ShortcutBinding) -> NSMenuItem? {
        menuItems(in: NSApp.mainMenu).first { item in
            guard !item.keyEquivalent.isEmpty else { return false }
            return ShortcutBinding(
                keyEquivalent: item.keyEquivalent,
                modifiers: item.keyEquivalentModifierMask) == binding
        }
    }

    private func menuItems(in menu: NSMenu?) -> [NSMenuItem] {
        guard let menu else { return [] }
        return menu.items.flatMap { item in
            [item] + menuItems(in: item.submenu)
        }
    }

    private func bindingTokens(for action: ShortcutAction) -> [String] {
        if recordingAction == action { return ["Type shortcut…"] }
        return preferences.shortcut(for: action)?.displayTokens ?? ["Record shortcut"]
    }

    private func bindingAccessibilityLabel(for action: ShortcutAction) -> String {
        if recordingAction == action { return "Cancel recording for \(action.label)" }
        if let binding = preferences.shortcut(for: action) {
            return "Record shortcut for \(action.label), current shortcut \(binding.accessibilityLabel)"
        }
        return "Record shortcut for \(action.label), unassigned"
    }

    private func optionCharacterWarning(for action: ShortcutAction) -> Bool {
        guard let binding = preferences.shortcut(for: action), binding.modifiers.contains(.option) else {
            return false
        }
        if case .character = binding.key { return true }
        return false
    }
}
