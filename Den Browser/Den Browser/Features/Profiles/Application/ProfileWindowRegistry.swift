import AppKit
import DenDomain

@MainActor
final class ProfileWindowRegistry {
    private var windows: [UUID: RegisteredWindow] = [:]
    private var stores: [UUID: DenStore] = [:]
    private var storeProfileIDs: [UUID: ProfileID] = [:]
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
        let store = stores.removeValue(forKey: windowID)
        let profileID = storeProfileIDs.removeValue(forKey: windowID) ?? registration?.profileID
        return RemovedProfileWindow(registration: registration, store: store, profileID: profileID)
    }

    func setStore(_ store: DenStore, windowID: UUID, profileID: ProfileID) {
        stores[windowID] = store
        storeProfileIDs[windowID] = profileID
    }

    func store(for windowID: UUID) -> DenStore? {
        stores[windowID]
    }

    func profileID(for windowID: UUID) -> ProfileID? {
        storeProfileIDs[windowID]
    }

    func store(for window: NSWindow) -> DenStore? {
        windowID(for: window).flatMap { stores[$0] }
    }

    func storeEntries() -> [(windowID: UUID, profileID: ProfileID?, store: DenStore)] {
        stores.map { windowID, store in
            (windowID, storeProfileIDs[windowID], store)
        }
    }

    func activeStore(preferredWindowID: UUID?) -> DenStore? {
        if let preferredWindowID {
            return stores[preferredWindowID]
        }
        return stores.values.first
    }

    func activeProfileID(preferredWindowID: UUID?) -> ProfileID? {
        if let preferredWindowID {
            return storeProfileIDs[preferredWindowID]
        }
        return stores.keys.first.flatMap { storeProfileIDs[$0] }
    }

    func store(forProfileID profileID: ProfileID, preferredWindowID: UUID?) -> DenStore? {
        if let preferredWindowID,
            storeProfileIDs[preferredWindowID] == profileID,
            let store = stores[preferredWindowID]
        {
            return store
        }
        for (windowID, candidateProfileID) in storeProfileIDs where candidateProfileID == profileID {
            if let store = stores[windowID] {
                return store
            }
        }
        return nil
    }

    func profileID(for store: DenStore) -> ProfileID? {
        for (windowID, candidateStore) in stores where candidateStore === store {
            return storeProfileIDs[windowID]
        }
        return nil
    }

    func stores(for profileID: ProfileID) -> [DenStore] {
        storeProfileIDs.compactMap { windowID, candidateProfileID in
            candidateProfileID == profileID ? stores[windowID] : nil
        }
    }

    func allStores() -> [DenStore] {
        Array(stores.values)
    }

    func hasStore(for profileID: ProfileID) -> Bool {
        storeProfileIDs.values.contains(profileID)
    }

    func storeWindowIDs(for profileID: ProfileID) -> Set<UUID> {
        Set(
            storeProfileIDs.compactMap { windowID, candidateProfileID in
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
    let store: DenStore?
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
