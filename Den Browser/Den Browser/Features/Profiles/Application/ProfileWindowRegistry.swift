import AppKit
import DenDomain

@MainActor
final class ProfileWindowRegistry {
    private var windows: [UUID: RegisteredWindow] = [:]
    private var controllers: [UUID: DenController] = [:]
    private var controllerProfileIDs: [UUID: ProfileID] = [:]
    var openWindowAction: ((ProfileWindowRoute) -> Void)?

    func register(window: NSWindow, profileID: ProfileID, windowID: UUID) {
        windows[windowID] = RegisteredWindow(profileID: profileID, window: window)
    }

    func matches(windowID: UUID, matchingWindow: NSWindow?) -> Bool {
        guard let matchingWindow else { return true }
        return windows[windowID]?.window === matchingWindow
    }

    func removeWindow(windowID: UUID) -> RemovedProfileWindow {
        let registration = windows.removeValue(forKey: windowID)
        let controller = controllers.removeValue(forKey: windowID)
        let profileID = controllerProfileIDs.removeValue(forKey: windowID) ?? registration?.profileID
        return RemovedProfileWindow(registration: registration, controller: controller, profileID: profileID)
    }

    func setController(_ controller: DenController, windowID: UUID, profileID: ProfileID) {
        controllers[windowID] = controller
        controllerProfileIDs[windowID] = profileID
    }

    func controller(for windowID: UUID) -> DenController? {
        controllers[windowID]
    }

    func profileID(for windowID: UUID) -> ProfileID? {
        controllerProfileIDs[windowID]
    }

    func controller(for window: NSWindow) -> DenController? {
        windowID(for: window).flatMap { controllers[$0] }
    }

    func controllerEntries() -> [(windowID: UUID, profileID: ProfileID?, controller: DenController)] {
        controllers.map { windowID, controller in
            (windowID, controllerProfileIDs[windowID], controller)
        }
    }

    func activeController(preferredWindowID: UUID?) -> DenController? {
        if let preferredWindowID {
            return controllers[preferredWindowID]
        }
        return controllers.values.first
    }

    func activeProfileID(preferredWindowID: UUID?) -> ProfileID? {
        if let preferredWindowID {
            return controllerProfileIDs[preferredWindowID]
        }
        return controllers.keys.first.flatMap { controllerProfileIDs[$0] }
    }

    func controller(forProfileID profileID: ProfileID, preferredWindowID: UUID?) -> DenController? {
        if let preferredWindowID,
            controllerProfileIDs[preferredWindowID] == profileID,
            let controller = controllers[preferredWindowID]
        {
            return controller
        }
        for (windowID, candidateProfileID) in controllerProfileIDs where candidateProfileID == profileID {
            if let controller = controllers[windowID] {
                return controller
            }
        }
        return nil
    }

    func profileID(for controller: DenController) -> ProfileID? {
        for (windowID, candidateController) in controllers where candidateController === controller {
            return controllerProfileIDs[windowID]
        }
        return nil
    }

    func controllers(for profileID: ProfileID) -> [DenController] {
        controllerProfileIDs.compactMap { windowID, candidateProfileID in
            candidateProfileID == profileID ? controllers[windowID] : nil
        }
    }

    func allControllers() -> [DenController] {
        Array(controllers.values)
    }

    func hasController(for profileID: ProfileID) -> Bool {
        controllerProfileIDs.values.contains(profileID)
    }

    func controllerWindowIDs(for profileID: ProfileID) -> Set<UUID> {
        Set(
            controllerProfileIDs.compactMap { windowID, candidateProfileID in
                candidateProfileID == profileID ? windowID : nil
            })
    }

    func windowID(for window: NSWindow) -> UUID? {
        windows.first(where: { $0.value.window === window })?.key
    }

    func window(for profileID: ProfileID) -> NSWindow? {
        NSApp.orderedWindows.first { candidate in
            windows.values.contains { $0.profileID == profileID && $0.window === candidate }
        } ?? windows.values.first { $0.profileID == profileID }?.window
    }

    func registeredWindow(for windowID: UUID) -> NSWindow? {
        windows[windowID]?.window
    }

    func presentationTarget() -> (windowID: UUID, registration: RegisteredWindow)? {
        if let keyWindow = NSApp.keyWindow,
            let target = windows.first(where: { $0.value.window === keyWindow })
        {
            return (target.key, target.value)
        }
        for window in NSApp.orderedWindows {
            if let target = windows.first(where: { $0.value.window === window }) {
                return (target.key, target.value)
            }
        }
        return nil
    }

    func hasWindow(for profileID: ProfileID) -> Bool {
        windows.values.contains { $0.profileID == profileID }
    }

    func windowIDs(for profileID: ProfileID) -> Set<UUID> {
        Set(
            windows.compactMap { windowID, registration in
                registration.profileID == profileID ? windowID : nil
            })
    }
}

struct RemovedProfileWindow {
    let registration: RegisteredWindow?
    let controller: DenController?
    let profileID: ProfileID?
}

final class RegisteredWindow {
    let profileID: ProfileID
    weak var window: NSWindow?

    init(profileID: ProfileID, window: NSWindow) {
        self.profileID = profileID
        self.window = window
    }
}
