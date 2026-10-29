import DenDomain
import DenModels
import SwiftUI

public struct DenDrawerOverlay<Peek: View>: View {
    let size: CGSize
    let profileColor: Color
    let shouldShowHeader: Bool

    private let drawerStyle: DrawerStyle
    private let motionPreference: MotionPreference
    private let peek: (DrawerItem, Bool) -> Peek
    private let placeFromContextMenu: (UUID) -> Void
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(
        size: CGSize, profileColor: Color, shouldShowHeader: Bool,
        drawerStyle: DrawerStyle, motionPreference: MotionPreference,
        @ViewBuilder peek: @escaping (DrawerItem, Bool) -> Peek,
        placeFromContextMenu: @escaping (UUID) -> Void
    ) {
        self.size = size
        self.profileColor = profileColor
        self.shouldShowHeader = shouldShowHeader
        self.drawerStyle = drawerStyle
        self.motionPreference = motionPreference
        self.peek = peek
        self.placeFromContextMenu = placeFromContextMenu
    }

    public var body: some View {
        let isBottom = drawerStyle == .bottom

        ZStack(alignment: isBottom ? .bottom : .center) {
            if windowModel.isDrawerPresented {
                dismissBlocker(onDismiss: windowModel.closeDrawer)
                    .transition(.opacity)

                DrawerView(
                    availableHeight: size.height,
                    availableWidth: size.width,
                    profileColor: profileColor,
                    shouldShowHeader: shouldShowHeader,
                    isDenMode: { windowModel.isDenMode },
                    isInputActive: { windowModel.isDrawerOpen },
                    motionPreference: motionPreference,
                    peek: peek, placeFromContextMenu: placeFromContextMenu,
                    placeAsBoard: { _ = windowModel.placeDrawerItemAsBoard($0) }
                )
                .padding(.horizontal, isBottom ? DenLayout.outerInset : 0)
                .transition(
                    isBottom
                        ? DenMotion.transition(reduceMotion: shouldReduceMotion, edge: .bottom)
                        : DenMotion.panelTransition(reduceMotion: shouldReduceMotion)
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(windowModel.isDrawerOpen)
        .accessibilityHidden(!windowModel.isDrawerOpen)
        .zIndex(DenOverlayLayer.drawer)
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}
