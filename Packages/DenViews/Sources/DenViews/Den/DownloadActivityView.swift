import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

public struct DownloadActivityView: View {
    let activity: DownloadActivity
    let tint: Color

    public init(activity: DownloadActivity, tint: Color) {
        self.activity = activity
        self.tint = tint
    }

    public var body: some View {
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
        .padding(.horizontal, DenFeedbackLayout.horizontalPadding)
        .padding(.vertical, DenFeedbackLayout.verticalPadding)
        .frame(width: DenFeedbackLayout.width, alignment: .leading)
        .glassEffect(
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
        )
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
