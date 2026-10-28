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

/// Trailing setting actions, placed after helper text and validation messages.
///
/// The caller owns draft/save behavior and the grouping of navigation and reset actions.
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

/// Shared settings explanation styling; content and input guidance remain feature-owned.
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
