import SwiftUI

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: toast.style.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toast.style.iconColor)

            VStack(alignment: .leading, spacing: 3) {
                if let title = toast.title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if !toast.body.isEmpty {
                    Text(toast.body)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: DenRadius.medium,
                style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
    }
}
