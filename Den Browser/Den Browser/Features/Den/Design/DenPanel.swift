import SFSafeSymbols
import SwiftUI

struct DenPanelHeader<Content: View>: View {
    private let icon: AnyView
    let content: Content

    init(systemSymbol: SFSymbol, @ViewBuilder content: () -> Content) {
        self.icon = AnyView(Image(systemSymbol: systemSymbol))
        self.content = content()
    }

    init<Icon: View>(icon: Icon, @ViewBuilder content: () -> Content) {
        self.icon = AnyView(icon)
        self.content = content()
    }

    var body: some View {
        HStack(spacing: DenPanelLayout.controlSpacing) {
            icon
                .foregroundStyle(.secondary)
            content
        }
        .frame(height: DenPanelLayout.titleHeight)
    }
}

extension View {
    func denPanel(width: CGFloat = DenPanelLayout.standardWidth) -> some View {
        padding(DenPanelLayout.padding)
            .frame(width: width)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
            )
    }
}

struct DenValidationMessage: View {
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
