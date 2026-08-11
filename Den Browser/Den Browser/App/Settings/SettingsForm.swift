import SwiftUI

struct SettingsForm<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Form(content: content)
            .formStyle(.grouped)
            .padding()
    }
}

struct SettingsActionRow<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            content()
        }
    }
}

struct SettingsHelpText<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct SettingsValidationMessage: View {
    private let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }
}
