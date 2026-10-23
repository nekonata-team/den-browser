import DenDomain
import DenPresentationModels
import DenViews
import SwiftUI

struct NewDeskPanel: View {
    let profileColor: Color
    var boardHeight: CGFloat = DenLayout.fallbackBoardHeight
    @Environment(DenController.self) private var controller
    var body: some View {
        DenViews.NewDeskPanel(
            profileColor: profileColor, boardHeight: boardHeight,
            facing: { controller.presetFacingStore.image(for: $0, at: $1) },
            loadFacings: { await controller.presetFacingStore.loadFacings(for: $0, boardCount: $1) })
    }
}

struct SaveDeskPresetPanel: View {
    let initialLabel: String
    let previewBoards: [DeskPresetBoard]
    var boardHeight: CGFloat = DenLayout.fallbackBoardHeight
    let savePreset: (String) -> DeskPresetSaveResult
    let onClose: () -> Void
    @Environment(DenController.self) private var controller
    var body: some View {
        DenViews.SaveDeskPresetPanel(
            initialLabel: initialLabel, previewBoards: previewBoards, boardHeight: boardHeight, savePreset: savePreset,
            facing: { index in
                guard let boards = controller.navigation.focusedDesk?.boards, boards.indices.contains(index) else {
                    return nil
                }
                return controller.facingCache.image(for: boards[index].id)
            }, captureFacings: { await controller.captureFocusedDeskFacings() }, onClose: onClose)
    }
}

struct DeskPresetManagementPanel: View {
    let isStandalone: Bool
    let profileColor: Color
    let presets: [PersonalDeskPreset]
    var boardHeight: CGFloat = DenLayout.fallbackBoardHeight
    let renamePreset: (UUID, String) -> DeskPresetRenameResult
    let requestDeletion: (UUID) -> Void
    let onClose: () -> Void
    @Environment(DenController.self) private var controller
    var body: some View {
        DenViews.DeskPresetManagementPanel(
            isStandalone: isStandalone, profileColor: profileColor, presets: presets, boardHeight: boardHeight,
            renamePreset: renamePreset, requestDeletion: requestDeletion,
            facing: { controller.presetFacingStore.image(for: $0, at: $1) },
            loadFacings: { await controller.presetFacingStore.loadFacings(for: $0, boardCount: $1) }, onClose: onClose)
    }
}
