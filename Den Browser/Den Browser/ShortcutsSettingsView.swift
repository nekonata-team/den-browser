import AppKit
import SwiftUI

struct ShortcutsSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var recordingAction: ShortcutAction?
    @State private var recordingMonitor: Any?
    @State private var errorMessage: String?
    @State private var isGuidePresented = false

    var body: some View {
        Form {
            Section("Shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    shortcutRow(action)
                }
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
                    .disabled(preferences.shortcutOverrides.isEmpty)
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

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(action.label)
                Spacer()

                Text(bindingLabel(for: action))
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .foregroundStyle(recordingAction == action ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(bindingAccessibilityLabel(for: action))

                Button(recordingAction == action ? "Type Shortcut…" : "Record…") {
                    startRecording(action)
                }
                .disabled(recordingAction == action)

                if action.canBeUnassigned {
                    Button("Clear") {
                        stopRecording()
                        preferences.clearShortcut(for: action)
                    }
                    .disabled(preferences.shortcut(for: action) == nil)
                }

                Button("Reset") {
                    stopRecording()
                    preferences.resetShortcut(for: action)
                }
                .disabled(!preferences.hasShortcutOverride(for: action))
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

    private func bindingLabel(for action: ShortcutAction) -> String {
        if recordingAction == action { return "Type shortcut…" }
        return preferences.shortcut(for: action)?.displayName ?? "Unassigned"
    }

    private func bindingAccessibilityLabel(for action: ShortcutAction) -> String {
        if recordingAction == action { return "Type shortcut" }
        return preferences.shortcut(for: action)?.accessibilityLabel ?? "Unassigned"
    }

    private func optionCharacterWarning(for action: ShortcutAction) -> Bool {
        guard let binding = preferences.shortcut(for: action), binding.modifiers.contains(.option) else {
            return false
        }
        if case .character = binding.key { return true }
        return false
    }
}
