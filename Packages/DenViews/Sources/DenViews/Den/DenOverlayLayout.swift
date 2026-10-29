import SwiftUI

public enum DenOverlayLayer {
    public static let activePanel: Double = 1
    public static let deskFilter: Double = 2
    public static let drawer: Double = 3
    public static let drawerInput: Double = 3.5
    public static let notificationDismissArea: Double = 4
    public static let notificationList: Double = 5
    public static let toast: Double = 10
}

public func dismissBlocker(onDismiss: @escaping () -> Void) -> some View {
    Color.clear
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityHidden(true)
}
