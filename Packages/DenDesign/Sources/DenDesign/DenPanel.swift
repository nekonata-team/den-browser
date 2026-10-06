public import SFSafeSymbols
import SwiftUI

public struct DenPanelHeader<Content: View>: View {
    private let icon: AnyView
    let content: Content

    public init(systemSymbol: SFSymbol, @ViewBuilder content: () -> Content) {
        self.icon = AnyView(Image(systemSymbol: systemSymbol))
        self.content = content()
    }

    public init<Icon: View>(icon: Icon, @ViewBuilder content: () -> Content) {
        self.icon = AnyView(icon)
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: DenPanelLayout.controlSpacing) {
            icon
                .foregroundStyle(.secondary)
            content
        }
        .frame(height: DenPanelLayout.titleHeight)
    }
}

extension View {
    public func denPanel(width: CGFloat = DenPanelLayout.standardWidth) -> some View {
        padding(DenPanelLayout.padding)
            .frame(width: width)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
            )
    }

    public func denPanelHeaderField() -> some View {
        labelsHidden()
            .textFieldStyle(.plain)
            .font(.title3.weight(.medium))
    }

    public func denSelectionHighlight(
        _ isSelected: Bool,
        profileColor: Color,
        inactiveOpacity: Double = 0
    ) -> some View {
        modifier(
            DenSelectionHighlight(
                isSelected: isSelected,
                profileColor: profileColor,
                inactiveOpacity: inactiveOpacity
            ))
    }
}

private struct DenSelectionHighlight: ViewModifier {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let isSelected: Bool
    let profileColor: Color
    let inactiveOpacity: Double

    private var selectionColor: Color { differentiateWithoutColor ? .primary : profileColor }

    func body(content: Content) -> some View {
        content
            .background(
                isSelected ? selectionColor.opacity(0.12) : Color.primary.opacity(inactiveOpacity),
                in: RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
                    .strokeBorder(isSelected ? selectionColor.opacity(0.8) : .clear, lineWidth: 1)
            }
    }
}

public struct DenValidationMessage: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }
}

public struct DenPanelHint: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
