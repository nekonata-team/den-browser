import DenApplication
import DenDomain
import DenPresentationModels
import DenViews
import SwiftUI

struct OverviewView: View {
    let profileColor: Color
    let boardHeight: CGFloat
    @Environment(ProfileWindowSession.self) private var session
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        DenViews.OverviewView(
            profileColor: profileColor, boardHeight: boardHeight,
            motionPreference: preferences.motionPreference,
            facing: { session.resources.facingCache.image(for: $0) },
            loadFacing: { await session.resources.facingCache.loadFacing(for: $0) })
    }
}
