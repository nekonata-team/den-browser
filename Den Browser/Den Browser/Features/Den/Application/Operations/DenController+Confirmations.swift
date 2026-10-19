import DenApplication
import DenDomain
import DenPresentationModels

extension DenController {
    @discardableResult
    func performConfirmedOperation(_ request: DenConfirmationRequest) -> Bool {
        switch request {
        case .resetDen:
            resetDen()
        case .deleteDesk(let desk):
            confirmDeskDeletion(desk.id)
        case .replaceDesk(let replacement):
            confirmDeskReplacement(replacement)
        case .deleteDeskPreset(let preset):
            deleteDeskPreset(preset.id)
        case .replaceDeskPreset(let replacement):
            return replaceDeskPreset(replacement)
        case .replaceEssential(_, let replacement):
            return replaceEssential(replacement)
        case .clearDrawer:
            clearDrawer()
        case .clearNotifications:
            clearNotifications()
        }
        return true
    }
}
