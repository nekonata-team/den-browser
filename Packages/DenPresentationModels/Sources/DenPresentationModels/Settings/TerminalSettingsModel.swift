import Foundation
import Observation

@MainActor
@Observable
public final class TerminalSettingsModel {
    @ObservationIgnored private let readZellijPath: () -> String
    @ObservationIgnored private let readZmxPath: () -> String
    @ObservationIgnored private let saveZellijPath: (String) -> Void
    @ObservationIgnored private let saveZmxPath: (String) -> Void
    @ObservationIgnored private let openPermissions: () -> Void

    public init(
        zellijPath: @escaping () -> String, zmxPath: @escaping () -> String,
        saveZellijPath: @escaping (String) -> Void, saveZmxPath: @escaping (String) -> Void,
        openPermissions: @escaping () -> Void
    ) {
        self.readZellijPath = zellijPath
        self.readZmxPath = zmxPath
        self.saveZellijPath = saveZellijPath
        self.saveZmxPath = saveZmxPath
        self.openPermissions = openPermissions
    }

    public var zellijPath: String { readZellijPath() }
    public var zmxPath: String { readZmxPath() }
    public func setZellijPath(_ path: String) { saveZellijPath(path) }
    public func setZmxPath(_ path: String) { saveZmxPath(path) }
    public func openFullDiskAccessSettings() { openPermissions() }
}
