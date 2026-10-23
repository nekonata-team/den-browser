public import DenApplication
import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class DeskListModel {
    @ObservationIgnored private let state: DenStateStore
    @ObservationIgnored private let lifecycle: DeskLifecycle
    @ObservationIgnored private let movement: DeskMovement
    @ObservationIgnored private let updates: DeskUpdates
    public let navigation: WindowNavigationModel
    @ObservationIgnored private let available: (DeskID) -> Bool
    @ObservationIgnored private let select: (DeskID) -> Void
    @ObservationIgnored private let notify: (DeskLifecycle.Notice) -> Void
    @ObservationIgnored private let didDuplicate: (DeskState, DeskState) -> Void
    @ObservationIgnored private let requestDeletion: (DeskState) -> Void
    @ObservationIgnored private let warn: (String) -> Void
    @ObservationIgnored private let finishEditing: () -> Void
    @ObservationIgnored private let copyID: (DeskID) -> Void
    @ObservationIgnored private let exportLinks: (DeskID) -> Void
    @ObservationIgnored private let copyLinks: (DeskID) -> Void

    @ObservationIgnored private let create: (String, DeskPresetSelection) -> Void
    @ObservationIgnored private let replace: (String, DeskPresetSelection) -> DeskReplacementResult?

    public init(
        state: DenStateStore, lifecycle: DeskLifecycle, movement: DeskMovement, updates: DeskUpdates,
        navigation: WindowNavigationModel, isAvailable: @escaping (DeskID) -> Bool,
        select: @escaping (DeskID) -> Void, notify: @escaping (DeskLifecycle.Notice) -> Void,
        didDuplicate: @escaping (DeskState, DeskState) -> Void,
        requestDeletion: @escaping (DeskState) -> Void, warn: @escaping (String) -> Void,
        finishEditing: @escaping () -> Void, copyID: @escaping (DeskID) -> Void,
        exportLinks: @escaping (DeskID) -> Void, copyLinks: @escaping (DeskID) -> Void,
        create: @escaping (String, DeskPresetSelection) -> Void,
        replace: @escaping (String, DeskPresetSelection) -> DeskReplacementResult?
    ) {
        self.create = create
        self.replace = replace
        self.state = state
        self.lifecycle = lifecycle
        self.movement = movement
        self.updates = updates
        self.navigation = navigation
        self.available = isAvailable
        self.select = select
        self.notify = notify
        self.didDuplicate = didDuplicate
        self.requestDeletion = requestDeletion
        self.warn = warn
        self.finishEditing = finishEditing
        self.copyID = copyID
        self.exportLinks = exportLinks
        self.copyLinks = copyLinks
    }

    public var deskPresets: [PersonalDeskPreset] { state.snapshot.deskPresets }
    public func createDesk(label: String, selection: DeskPresetSelection) { create(label, selection) }
    public func replaceDesk(label: String, selection: DeskPresetSelection) -> DeskReplacementResult? {
        replace(label, selection)
    }

    public var desks: [DeskState] { state.snapshot.den.desks }
    public var presentedDeskID: DeskID { navigation.presentedDeskID }
    public var focusedDesk: DeskState? { desks.first { $0.id == presentedDeskID } }
    public var canCreateDesk: Bool { lifecycle.canCreate }
    public var canDeleteFocusedDesk: Bool { lifecycle.canDelete(presentedDeskID, isAvailable: available) }
    public func canSelectDesk(_ id: DeskID) -> Bool { id == presentedDeskID || available(id) }
    public var canExportFocusedDeskLinks: Bool {
        guard let desk = focusedDesk else { return false }
        return canExportDeskLinks(for: desk.id)
    }
    public func canExportDeskLinks(for id: DeskID) -> Bool {
        desks.first { $0.id == id }?.boards.contains { $0.currentSheetURL != nil } == true
    }
    public func focusDesk(_ id: DeskID) { select(id) }
    public func copyDeskID(_ id: DeskID) { copyID(id) }
    public func exportDeskLinks(for id: DeskID) { exportLinks(id) }
    public func copyDeskLinks(for id: DeskID) { copyLinks(id) }
    public func beginDeskDrag(_ id: DeskID) -> Bool { movement.beginDrag(id) }
    public func previewDeskMove(_ id: DeskID, to index: DeskIndex) { movement.preview(id, to: index) }
    public func restoreDeskOrder(_ ids: [DeskID]) { movement.restoreOrder(ids) }
    public func finishDeskDrag() { movement.finishDrag() }
    public func moveDesk(_ id: DeskID, by delta: Int) { movement.move(id, by: delta) }

    public func duplicateDesk(_ id: DeskID) {
        guard let result = lifecycle.duplicate(id, presentedDeskID: presentedDeskID, notify: notify) else { return }
        didDuplicate(result.source, result.copy)
    }

    public func deleteFocusedDesk() {
        guard canDeleteFocusedDesk else {
            warn("The last desk cannot be deleted.")
            return
        }
        guard let desk = focusedDesk else { return }
        if desk.boards.isEmpty {
            lifecycle.delete(desk.id, presentedDeskID: presentedDeskID, isAvailable: available, notify: notify)
        } else {
            requestDeletion(desk)
        }
    }

    public func renameFocusedDesk(to label: String) {
        updates.rename(presentedDeskID, to: label, notify: finishEditing)
    }
}
