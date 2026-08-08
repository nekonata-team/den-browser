import SwiftUI

struct DenPanelHeader<Content: View>: View {
    let systemImage: String
    let content: Content

    init(systemImage: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(spacing: DenPanelLayout.controlSpacing) {
            Image(systemName: systemImage)
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
