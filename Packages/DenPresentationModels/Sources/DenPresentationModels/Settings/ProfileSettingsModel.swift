import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class ProfileSettingsModel {
    @ObservationIgnored private let readProfiles: () -> [ProfileState]
    @ObservationIgnored private let readError: () -> String?
    @ObservationIgnored private let canDelete: (ProfileID) -> Bool
    @ObservationIgnored private let create: (String, ProfileColor) -> ProfileState?
    @ObservationIgnored private let update: (ProfileID, String?, ProfileColor?) -> Bool
    @ObservationIgnored private let delete: (ProfileID) async -> Bool
    @ObservationIgnored private let dismissError: () -> Void
    @ObservationIgnored private let clearSelection: () -> ProfileID?
    @ObservationIgnored private let requestClear: (ProfileID) -> Void
    @ObservationIgnored private let dismissClear: () -> Void
    @ObservationIgnored private let clear: (Set<BrowsingDataCategory>, ProfileID) async -> Bool

    public init(
        profiles: @escaping () -> [ProfileState], error: @escaping () -> String?,
        canDelete: @escaping (ProfileID) -> Bool, create: @escaping (String, ProfileColor) -> ProfileState?,
        update: @escaping (ProfileID, String?, ProfileColor?) -> Bool, delete: @escaping (ProfileID) async -> Bool,
        dismissError: @escaping () -> Void, clearSelection: @escaping () -> ProfileID?,
        requestClear: @escaping (ProfileID) -> Void, dismissClear: @escaping () -> Void,
        clear: @escaping (Set<BrowsingDataCategory>, ProfileID) async -> Bool
    ) {
        self.readProfiles = profiles
        self.readError = error
        self.canDelete = canDelete
        self.create = create
        self.update = update
        self.delete = delete
        self.dismissError = dismissError
        self.clearSelection = clearSelection
        self.requestClear = requestClear
        self.dismissClear = dismissClear
        self.clear = clear
    }

    public var profiles: [ProfileState] { readProfiles() }
    public var errorMessage: String? { readError() }
    public var clearBrowsingDataProfileID: ProfileID? { clearSelection() }
    public func profile(id: ProfileID) -> ProfileState? { profiles.first { $0.id == id } }
    public func canDeleteProfile(_ id: ProfileID) -> Bool { canDelete(id) }
    public func createProfile(name: String, color: ProfileColor) -> ProfileState? { create(name, color) }
    public func updateProfile(_ id: ProfileID, name: String? = nil, color: ProfileColor? = nil) -> Bool {
        update(id, name, color)
    }
    public func deleteProfile(_ id: ProfileID) async -> Bool { await delete(id) }
    public func clearError() { dismissError() }
    public func requestClearBrowsingData(_ id: ProfileID) { requestClear(id) }
    public func dismissClearBrowsingData() { dismissClear() }
    public func clearBrowsingData(categories: Set<BrowsingDataCategory>, profileID: ProfileID) async -> Bool {
        await clear(categories, profileID)
    }
}
