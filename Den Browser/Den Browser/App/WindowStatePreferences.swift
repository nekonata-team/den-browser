import Foundation

// TODO: Remove this cleanup, its startup call, and its tests once upgrades from builds
// without the stable profile-window scene ID no longer need support. Keep the scene ID.
enum WindowStatePreferences {
    static func removeLegacyProfileState(defaults: UserDefaults, domainName: String) {
        guard let domain = defaults.persistentDomain(forName: domainName) else { return }
        for key in domain.keys {
            let isWindowState =
                key.hasPrefix("NSWindow Frame SwiftUI.")
                || key.hasPrefix("NSSplitView Subview Frames SwiftUI.")
            guard isWindowState && key.contains(".ProfileWindowView,") else { continue }
            // A bulk replacement can exceed CFPreferences' request limit when removing long keys.
            defaults.removeObject(forKey: key)
        }
    }
}
