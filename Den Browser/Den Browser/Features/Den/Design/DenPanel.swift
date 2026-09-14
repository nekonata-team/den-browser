import SFSafeSymbols
import SwiftUI

struct DenPanelHeader<Content: View>: View {
    let systemSymbol: SFSymbol
    let content: Content

    init(systemSymbol: SFSymbol, @ViewBuilder content: () -> Content) {
        self.systemSymbol = systemSymbol
        self.content = content()
    }

    var body: some View {
        HStack(spacing: DenPanelLayout.controlSpacing) {
            Image(systemSymbol: systemSymbol)
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
