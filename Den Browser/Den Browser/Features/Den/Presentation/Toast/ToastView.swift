import SFSafeSymbols
import SwiftUI

struct ToastView: View {
    let toast: ToastMessage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemSymbol: toast.style.systemSymbol)
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
        }
        .buttonStyle(.plain)
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
        .accessibilityHint(toast.target == nil ? "Dismiss notification" : "Open notification target")
    }
}

struct DownloadActivityView: View {
    let activity: DownloadActivity
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemSymbol: .arrowDownCircle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(activity.filename)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if let fractionCompleted = activity.fractionCompleted {
                    Text(fractionCompleted, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Downloading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let fractionCompleted = activity.fractionCompleted {
                ProgressView(value: fractionCompleted)
                    .progressViewStyle(.linear)
                    .tint(tint)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(tint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 320, alignment: .leading)
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
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Downloading \(activity.filename)")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        activity.fractionCompleted?.formatted(.percent.precision(.fractionLength(0)))
            ?? "In progress"
    }
}
