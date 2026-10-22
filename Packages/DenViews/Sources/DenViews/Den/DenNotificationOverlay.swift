import DenPresentationModels
import SwiftUI

public struct DenNotificationOverlay: View {
    let profileColor: Color
    let shouldShowHeader: Bool

    @Environment(DenWindowModel.self) private var windowModel
    @Environment(AppearanceModel.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(profileColor: Color, shouldShowHeader: Bool) {
        self.profileColor = profileColor
        self.shouldShowHeader = shouldShowHeader
    }

    public var body: some View {
        if windowModel.isNotificationListPresented, windowModel.isZenViewPresented {
            dismissBlocker(onDismiss: windowModel.closeNotificationList)
                .zIndex(DenOverlayLayer.notificationDismissArea)

            NotificationListView(
                profileColor: profileColor
            )
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
            )
            .padding(
                .top,
                shouldShowHeader
                    ? DenLayout.denHeaderHeight + DenLayout.panelGap
                    : DenLayout.outerInset
            )
            .padding(.trailing, DenLayout.outerInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .transition(DenMotion.panelTransition(reduceMotion: shouldReduceMotion))
            .zIndex(DenOverlayLayer.notificationList)
        }
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}
