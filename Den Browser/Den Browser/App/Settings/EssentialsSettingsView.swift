import SwiftUI

struct EssentialsSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var editingEssential: EssentialEditorState?
    @State private var errorMessage: String?

    var body: some View {
        SettingsForm {
            Section("Essentials") {
                if preferences.essentials.isEmpty {
                    Text("No Essentials configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preferences.essentials) { essential in
                        essentialRow(essential)
                    }
                }

                SettingsActionRow {
                    Button("Add Essential") {
                        errorMessage = nil
                        editingEssential = EssentialEditorState(essential: nil)
                    }
                }

                if let errorMessage {
                    SettingsValidationMessage(errorMessage)
                }
            }

            SettingsHelpText {
                Text("Press g followed by an Essential key in Den Mode to start a Board.")
            }
        }
        .sheet(item: $editingEssential) { editor in
            EssentialEditorView(essential: editor.essential) { name, key, input in
                saveEssential(
                    id: editor.essential?.id,
                    name: name,
                    key: key,
                    input: input)
            }
        }
    }

    private func essentialRow(_ essential: Essential) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(essential.name)
                Text(essential.input)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            ShortcutChip(tokens: [essential.displayKey], width: 42)

            Button {
                errorMessage = nil
                editingEssential = EssentialEditorState(essential: essential)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit Essential \(essential.name)")

            Button {
                deleteEssential(essential)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete Essential \(essential.name)")
        }
    }

    private func saveEssential(
        id: UUID?,
        name: String,
        key: String,
        input: String
    ) -> String? {
        let essential = Essential(id: id ?? UUID(), name: name, key: key, input: input)
        guard essential.isValid else { return "Enter a name, one key, and an input." }

        var updated = preferences.essentials
        if let id {
            guard let index = updated.firstIndex(where: { $0.id == id }) else {
                return "The Essential no longer exists."
            }
            updated[index] = essential
        } else {
            updated.append(essential)
        }

        if updated.contains(where: { $0.id != essential.id && $0.key == essential.key }) {
            return "That key is already assigned to another Essential."
        }
        guard preferences.setEssentials(updated) else {
            return "Could not save the Essential."
        }
        errorMessage = nil
        editingEssential = nil
        return nil
    }

    private func deleteEssential(_ essential: Essential) {
        var updated = preferences.essentials
        updated.removeAll { $0.id == essential.id }
        guard preferences.setEssentials(updated) else {
            errorMessage = "Could not delete the Essential."
            return
        }
        errorMessage = nil
    }
}

private struct EssentialEditorState: Identifiable {
    let id: UUID
    let essential: Essential?

    init(essential: Essential?) {
        id = essential?.id ?? UUID()
        self.essential = essential
    }
}

private struct EssentialEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let essential: Essential?
    let onSave: (String, String, String) -> String?

    @State private var name: String
    @State private var key: String
    @State private var input: String
    @State private var errorMessage: String?

    init(essential: Essential?, onSave: @escaping (String, String, String) -> String?) {
        self.essential = essential
        self.onSave = onSave
        _name = State(initialValue: essential?.name ?? "")
        _key = State(initialValue: essential?.key ?? "")
        _input = State(initialValue: essential?.input ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(essential == nil ? "Add Essential" : "Edit Essential")
                .font(.headline)

            Form {
                TextField("Name", text: $name, prompt: Text("e.g. ChatGPT"))
                TextField("Key", text: $key, prompt: Text("e.g. c or C"))
                    .onChange(of: key) { _, value in
                        if value.count > 1 {
                            key = String(value.prefix(1))
                        }
                    }
                TextField(
                    "Input",
                    text: $input,
                    prompt: Text("URL, search, :terminal, :zellij, or :zmx"))
                SettingsHelpText {
                    Text(
                        "Keys are case-sensitive; hold Shift for uppercase. "
                            + "Examples: c, C, https://chatgpt.com, :terminal ~/Projects, :zellij work, :zmx work")
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                SettingsValidationMessage(errorMessage)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func save() {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = key == " " ? key : key.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, key.count == 1, !input.isEmpty else {
            errorMessage = "Enter a name, one key, and an input."
            return
        }
        if let errorMessage = onSave(name, key, input) {
            self.errorMessage = errorMessage
        } else {
            dismiss()
        }
    }
}
