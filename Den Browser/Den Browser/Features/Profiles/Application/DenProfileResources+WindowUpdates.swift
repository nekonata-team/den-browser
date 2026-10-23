import DenApplication
import DenDomain
import DenInfrastructure
import DenPresentationModels
import Foundation

extension DenProfileResources {
    @discardableResult
    func save() -> Bool {
        let signpost = PerformanceTrace.beginInterval("DenProfileResources.save")
        defer { PerformanceTrace.endInterval("DenProfileResources.save", signpost) }
        guard activeDrag == nil else { return false }
        return onSave?(DenStateNormalization.normalize(state)) ?? false
    }

    func saveDeferredState() {
        guard activeDrag == nil else { return }
        if let onDeferredSave {
            onDeferredSave()
        } else {
            _ = save()
        }
    }

    @discardableResult
    func saveDeskPresets() -> Bool {
        onDeskPresetsSave?(deskPresets) ?? false
    }

    func recordOperation(_ event: DenOperationEvent) {
        if let step = event.tutorialStep { tutorialProgress.record(step) }
        onDenOperationEvent(event)
    }

    func invalidateReferences(toRemovedBoardIDs ids: Set<BoardID>) {
        for window in windowConnections.allObjects {
            window.invalidateBoards?(ids)
            for id in ids { window.onWindowEffect?(.boardRemoved(id)) }
        }
        if case .board(let id) = activeDrag, ids.contains(id) { activeDrag = nil }
    }

    func invalidateReferences(toRemovedDeskID id: DeskID) {
        for window in windowConnections.allObjects {
            window.invalidateDesk?(id)
            window.onWindowEffect?(.deskRemoved(id))
        }
        if case .desk(let draggedID) = activeDrag, draggedID == id { activeDrag = nil }
    }
}
