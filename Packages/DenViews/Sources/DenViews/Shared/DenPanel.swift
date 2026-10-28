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
    /// Panel chrome: shared padding, width, Glass, and suppression of automatic focus rings.
    ///
    /// Retains system control styling and keyboard focus behavior; does not position the panel.
    public func denPanel(width: CGFloat = DenPanelLayout.standardWidth) -> some View {
        padding(DenPanelLayout.padding)
            .focusEffectDisabled()
            .frame(width: width)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
            )
    }

    /// Header input styling.
    ///
    /// The caller still supplies a meaningful label and an explicit prompt.
    public func denPanelHeaderField() -> some View {
        labelsHidden()
            .textFieldStyle(.plain)
            .font(.title3.weight(.medium))
    }

    /// Panel candidate-row selection, including the Differentiate Without Color treatment.
    ///
    /// Enable `showsInactiveBackground` when unselected rows need a subtle surface; do not add local opacity.
    public func denSelectionHighlight(
        _ isSelected: Bool,
        profileColor: Color,
        showsInactiveBackground: Bool = false
    ) -> some View {
        modifier(
            DenSelectionHighlight(
                isSelected: isSelected,
                profileColor: profileColor,
                showsInactiveBackground: showsInactiveBackground
            ))
    }
}

private struct DenSelectionHighlight: ViewModifier {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let isSelected: Bool
    let profileColor: Color
    let showsInactiveBackground: Bool

    private var selectionColor: Color { differentiateWithoutColor ? .primary : profileColor }

    func body(content: Content) -> some View {
        content
            .background(
                isSelected
                    ? selectionColor.opacity(DenSurfaceColors.selectionOpacity)
                    : Color.primary.opacity(showsInactiveBackground ? 0.04 : 0),
                in: RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
                    .strokeBorder(
                        isSelected ? selectionColor.opacity(DenSurfaceColors.emphasisOpacity) : .clear, lineWidth: 1)
            }
    }
}

/// Inline validation beside the editable draft in a panel or settings section.
///
/// The caller owns validation; action failures without form context use action feedback instead.
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

/// Keyboard navigation and action hints at the bottom of a panel; omit its opening shortcut.
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
