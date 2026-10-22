import DenDomain
import DenPresentationModels
import SwiftUI

public struct DenFeedbackOverlay: View {
    let profileColor: Color
    let shouldReduceMotion: Bool

    @Environment(DenWindowModel.self) private var windowModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private let activities: [DownloadActivity]

    public init(profileColor: Color, shouldReduceMotion: Bool, activities: [DownloadActivity]) {
        self.profileColor = profileColor
        self.shouldReduceMotion = shouldReduceMotion
        self.activities = activities
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(activities) { activity in
                DownloadActivityView(activity: activity, tint: profileColor)
                    .transition(feedbackTransition)
            }

            if let toast = windowModel.displayedFeedback {
                ToastView(toast: toast) {
                    windowModel.handleTap(on: toast)
                }
                .transition(feedbackTransition)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(
            windowModel.displayedFeedback == nil ? .easeIn(duration: 0.15) : .easeOut(duration: 0.15),
            value: windowModel.displayedFeedback?.id
        )
        .animation(
            DenMotion.feedback(reduceMotion: shouldReduceMotion),
            value: activities.map(\.id)
        )
    }

    private var feedbackTransition: AnyTransition {
        systemReduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }
}
