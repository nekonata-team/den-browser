import DenDesign
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

struct ToastView: View {
    let toast: DenFeedback
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemSymbol: feedbackSymbol(for: toast.severity))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(feedbackIconColor(for: toast.severity))

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
        .glassEffect(
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
        .accessibilityHint(toast.target == nil ? "Dismiss notification" : "Open notification target")
    }
}
