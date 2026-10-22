import DenDomain
import DenViews
import SwiftUI

struct OverviewView: View {
    let profileColor: Color
    let boardHeight: CGFloat
    @Environment(DenController.self) private var controller
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        DenViews.OverviewView(
            profileColor: profileColor, boardHeight: boardHeight,
            motionPreference: preferences.motionPreference,
            facing: { controller.facingCache.image(for: $0) },
            loadFacing: { await controller.facingCache.loadFacing(for: $0) })
    }
}
