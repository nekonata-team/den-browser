import AppKit
import DenApplication
import DenDomain
import DenPresentationModels

@MainActor
final class ProfileWindowRegistry {
    private var windows: [UUID: RegisteredWindow] = [:]
    private var sessions: [UUID: ProfileWindowSession] = [:]
    private var sessionProfileIDs: [UUID: ProfileID] = [:]
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
        let session = sessions.removeValue(forKey: windowID)
        let profileID = sessionProfileIDs.removeValue(forKey: windowID) ?? registration?.profileID
        return RemovedProfileWindow(registration: registration, session: session, profileID: profileID)
    }

    func setSession(_ session: ProfileWindowSession, windowID: UUID, profileID: ProfileID) {
        sessions[windowID] = session
        sessionProfileIDs[windowID] = profileID
    }

    func session(for windowID: UUID) -> ProfileWindowSession? {
        sessions[windowID]
    }

    func profileID(for windowID: UUID) -> ProfileID? {
        sessionProfileIDs[windowID]
    }

    func session(for window: NSWindow) -> ProfileWindowSession? {
        windowID(for: window).flatMap { sessions[$0] }
    }

    func sessionEntries() -> [(windowID: UUID, profileID: ProfileID?, session: ProfileWindowSession)] {
        sessions.map { windowID, session in
            (windowID, sessionProfileIDs[windowID], session)
        }
    }

    func activeSession(preferredWindowID: UUID?) -> ProfileWindowSession? {
        if let preferredWindowID {
            return sessions[preferredWindowID]
        }
        return sessions.values.first
    }

    func activeProfileID(preferredWindowID: UUID?) -> ProfileID? {
        if let preferredWindowID {
            return sessionProfileIDs[preferredWindowID]
        }
        return sessions.keys.first.flatMap { sessionProfileIDs[$0] }
    }

    func session(forProfileID profileID: ProfileID, preferredWindowID: UUID?) -> ProfileWindowSession? {
        if let preferredWindowID,
            sessionProfileIDs[preferredWindowID] == profileID,
            let session = sessions[preferredWindowID]
        {
            return session
        }
        for (windowID, candidateProfileID) in sessionProfileIDs where candidateProfileID == profileID {
            if let session = sessions[windowID] {
                return session
            }
        }
        return nil
    }

    func profileID(for session: ProfileWindowSession) -> ProfileID? {
        for (windowID, candidateSession) in sessions where candidateSession === session {
            return sessionProfileIDs[windowID]
        }
        return nil
    }

    func sessions(for profileID: ProfileID) -> [ProfileWindowSession] {
        sessionProfileIDs.compactMap { windowID, candidateProfileID in
            candidateProfileID == profileID ? sessions[windowID] : nil
        }
    }

    func allSessions() -> [ProfileWindowSession] {
        Array(sessions.values)
    }

    func hasSession(for profileID: ProfileID) -> Bool {
        sessionProfileIDs.values.contains(profileID)
    }

    func sessionWindowIDs(for profileID: ProfileID) -> Set<UUID> {
        Set(
            sessionProfileIDs.compactMap { windowID, candidateProfileID in
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
    let session: ProfileWindowSession?
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
