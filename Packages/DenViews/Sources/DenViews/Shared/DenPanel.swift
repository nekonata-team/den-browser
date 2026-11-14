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
            )
        )
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
                        isSelected ? selectionColor.opacity(DenSurfaceColors.emphasisOpacity) : .clear,
                        lineWidth: 1
                    )
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

/// Shared filter/search input with leading symbol, consistent surface styling, and IME sync.
public struct DenFilterField: View {
    @Binding private var text: String
    private let prompt: String
    private let accessibilityLabel: String
    private let accessibilityIdentifier: String?
    private let isActive: Bool
    private let profileColor: Color
    private let trailingHint: String?
    private let isFocused: FocusState<Bool>.Binding
    private let onTapInactive: (() -> Void)?

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    public init(
        text: Binding<String>,
        prompt: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String? = nil,
        isActive: Bool = true,
        profileColor: Color = .primary,
        trailingHint: String? = nil,
        isFocused: FocusState<Bool>.Binding,
        onTapInactive: (() -> Void)? = nil
    ) {
        self._text = text
        self.prompt = prompt
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.isActive = isActive
        self.profileColor = profileColor
        self.trailingHint = trailingHint
        self.isFocused = isFocused
        self.onTapInactive = onTapInactive
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .magnifyingglass)
                .foregroundStyle(isActive ? .primary : .secondary)
                .accessibilityHidden(true)

            inputField

            if let trailingHint {
                Text(trailingHint)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            DenSurfaceColors.filterInputBackground(isActive: isActive),
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .stroke(
                    DenSurfaceColors.filterInputBorder(
                        isActive: isActive,
                        profileColor: profileColor,
                        differentiateWithoutColor: differentiateWithoutColor
                    ),
                    lineWidth: isActive ? 1.5 : 1
                )
        }
        .onChange(of: text) { _, newValue in
            if isFocused.wrappedValue {
                TextInputComposition.syncActiveFieldEditor(to: newValue)
            }
        }
        .onTapGesture {
            if !isActive {
                onTapInactive?()
            }
        }
    }

    @ViewBuilder
    private var inputField: some View {
        let field = TextField(text: $text, prompt: Text(prompt)) {
            Text(accessibilityLabel)
        }
        .labelsHidden()
        .textFieldStyle(.plain)
        .focused(isFocused)
        .disabled(!isActive)

        if let accessibilityIdentifier {
            field.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            field
        }
    }
}
