import AppKit
import SFSafeSymbols
import SwiftUI

public struct SkillsSettingsView: View {
    private let installCommand: String
    private let updateCommand: String
    private let install: () -> String?
    private let update: () -> String?
    @State private var errorMessage: String?
    @State private var copiedCommand: String?

    public init(
        installCommand: String, updateCommand: String,
        install: @escaping () -> String?, update: @escaping () -> String?
    ) {
        self.installCommand = installCommand
        self.updateCommand = updateCommand
        self.install = install
        self.update = update
    }

    public var body: some View {
        SettingsForm {
            Section("Den Agent Skill") {
                Text("Let coding agents operate Den using the official den skill.")

                SettingsHelpText {
                    Text("Global installation. Requires Node.js.")
                }
                commandRow("Install", command: installCommand, run: install)
                commandRow("Update", command: updateCommand, run: update)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func commandRow(_ title: String, command: String, run: @escaping () -> String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack(alignment: .top, spacing: 12) {
                Text(command)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    if NSPasteboard.general.setString(command, forType: .string) {
                        copiedCommand = command
                        errorMessage = nil
                    } else {
                        errorMessage = "Could not copy the command."
                    }
                } label: {
                    Image(systemSymbol: copiedCommand == command ? .checkmark : .documentOnDocument)
                        .frame(width: 16, height: 16)
                }
                .accessibilityLabel("Copy \(title.lowercased()) command")
                .accessibilityValue(copiedCommand == command ? "Copied" : "")
                .help(copiedCommand == command ? "Copied" : "Copy command")
            }
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: DenRadius.small))
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.small)
                    .strokeBorder(.quaternary)
            }
            SettingsActionRow {
                Button("Run in Terminal Board…") { errorMessage = run() }
                    .accessibilityLabel("Run \(title.lowercased()) in Terminal Board")
            }
        }
    }
}
