import SwiftUI

public struct SettingsForm<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        Form(content: content)
            .formStyle(.grouped)
            .padding()
    }
}

public struct SettingsActionRow<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        HStack {
            Spacer(minLength: 0)
            content()
        }
    }
}

public struct SettingsHelpText<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
