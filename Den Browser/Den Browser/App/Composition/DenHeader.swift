import DenApplication
import DenDomain
import DenModels
import DenViews
import SwiftUI

struct DenHeader: View {
    let profile: ProfileState
    let windowID: UUID
    @Environment(ProfileWindowSession.self) private var session
    @Environment(DenWindowModel.self) private var windowModel
    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DenViews.DenHeader(
            profileColor: profileDisplayColor(for: profile.color),
            canOpenInNewWindow: {
                profileManager.canOpenDeskInNewWindow($0, profileID: profile.id, sourceWindowID: windowID)
            },
            isPresentedInAnotherWindow: {
                profileManager.isDeskPresentedInAnotherWindow($0, profileID: profile.id, excludingWindowID: windowID)
            },
            onOpenInNewWindow: { deskID in
                guard
                    let route = profileManager.routeForOpeningDesk(
                        deskID, profileID: profile.id, sourceWindowID: windowID)
                else { return }
                openWindow(value: route)
            },
            onNotificationKeyPress: {
                KeyboardController.handleNotificationKeyPress($0, session: session, windowModel: windowModel)
            }, restoreInput: { session.runtimes.restoreFocusedFirstResponder() },
            profileMenu: {
                ProfileMenu(
                    profile: profile, profiles: profileManager.profiles,
                    openProfile: { _ = profileManager.openWindow(for: $0) },
                    clearBrowsingData: {
                        profileManager.clearBrowsingDataProfileID = profile.id
                        profileManager.clearBrowsingDataWindowID = windowID
                    })
            })
    }
}
