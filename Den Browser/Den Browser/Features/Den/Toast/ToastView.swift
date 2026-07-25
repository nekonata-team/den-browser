import SwiftUI

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.style.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toast.style.iconColor)

            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
