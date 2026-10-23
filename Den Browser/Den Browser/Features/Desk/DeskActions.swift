import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
final class DeskActions {
    private let context: WindowNativeContext
    private let boardNavigation: BoardNavigation
    private var runtimes: BoardRuntimeAccess { context.runtimes }
    private var storage: DenProfileResources { context.storage }
    private var state: DenState { context.storage.state }
    private var pasteboard: NSPasteboard { context.pasteboard }
    private var focusedDesk: DeskState? { context.focusedDesk }
    private var presentedDeskID: DeskID { context.navigation.presentedDeskID }
    private var navigation: WindowNavigationBindings { context.navigation }
    private var deskPresets: [PersonalDeskPreset] { context.storage.deskPresets }
    private var facingCache: BoardFacingCache { context.storage.facingCache }
    private var canDeleteFocusedDesk: Bool {
        context.storage.deskLifecycle.canDelete(
            context.navigation.presentedDeskID, isAvailable: { context.canPresentDesk?($0) ?? true })
    }
    private var canPresentDesk: ((DeskID) -> Bool)? { context.canPresentDesk }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }

    init(context: WindowNativeContext, boardNavigation: BoardNavigation) {
        self.context = context
        self.boardNavigation = boardNavigation
    }

    @discardableResult
    func createDesk(
        label: String, preset: BuiltInDeskPreset, after deskID: DeskID? = nil, focus: Bool = true
    ) -> DeskState? {
        createDesk(
            label: label, boards: preset.boards, focusedBoardIndex: preset.focusedBoardIndex,
            after: deskID, focus: focus)
    }

    func createDesk(label: String, personalPresetID: UUID) {
        guard let preset = deskPresets.first(where: { $0.id == personalPresetID }) else { return }
        createDesk(label: label, boards: preset.boards, focusedBoardIndex: preset.focusedBoardIndex)
    }

    func duplicateDesk(_ deskID: DeskID) {
        guard
            let duplication = storage.deskLifecycle.duplicate(
                deskID, presentedDeskID: presentedDeskID, notify: deskLifecycleNotifications())
        else { return }
        for (original, duplicate) in zip(duplication.source.boards.filter { !$0.isTutorial }, duplication.copy.boards) {
            if let image = facingCache.image(for: original.id) {
                facingCache.setFacing(image, for: duplicate.id, at: nil)
            }
        }
    }

    @discardableResult
    private func createDesk(
        label: String, boards: [DeskPresetBoard], focusedBoardIndex: BoardIndex?, after deskID: DeskID? = nil,
        focus: Bool = true
    ) -> DeskState? {
        storage.deskLifecycle.create(
            label: label, boards: boards, focusedBoardIndex: focusedBoardIndex,
            presentedDeskID: presentedDeskID, after: deskID, focus: focus, notify: deskLifecycleNotifications())
    }

    func replaceFocusedDesk(label: String, preset: BuiltInDeskPreset) -> DeskReplacementResult {
        requestFocusedDeskReplacement(
            label: label,
            presetLabel: preset.label,
            boards: preset.boards,
            focusedBoardIndex: preset.focusedBoardIndex)
    }

    func replaceFocusedDesk(label: String, personalPresetID: UUID) -> DeskReplacementResult? {
        guard let preset = deskPresets.first(where: { $0.id == personalPresetID }) else { return nil }
        return requestFocusedDeskReplacement(
            label: label,
            presetLabel: preset.label,
            boards: preset.boards,
            focusedBoardIndex: preset.focusedBoardIndex)
    }

    func confirmDeskReplacement(_ replacement: PendingDeskReplacement) {
        applyDeskReplacement(replacement)
    }

    private func requestFocusedDeskReplacement(
        label: String,
        presetLabel: String,
        boards: [DeskPresetBoard],
        focusedBoardIndex: BoardIndex?
    ) -> DeskReplacementResult {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !label.isEmpty,
            !boards.isEmpty,
            let desk = focusedDesk
        else { return .unavailable }

        let replacement = PendingDeskReplacement(
            deskID: desk.id,
            originalLabel: desk.label,
            originalBoardCount: desk.boards.count,
            presetLabel: presetLabel,
            label: label,
            boards: boards,
            focusedBoardIndex: focusedBoardIndex)
        guard !desk.boards.isEmpty else {
            applyDeskReplacement(replacement)
            return .applied
        }
        onWindowEffect?(.requestConfirmation(.replaceDesk(replacement)))
        return .confirmationPending
    }

    private func applyDeskReplacement(_ replacement: PendingDeskReplacement) {
        guard
            storage.deskLifecycle.replace(
                replacement.deskID, label: replacement.label, boards: replacement.boards,
                focusedBoardIndex: replacement.focusedBoardIndex, notify: deskLifecycleNotifications())
        else { return }
        context.feedback.publish("Replaced Desk with Preset.", severity: .success)
    }

    func deleteFocusedDesk() {
        guard canDeleteFocusedDesk else {
            context.feedback.publish("The last desk cannot be deleted.", severity: .warning)
            return
        }
        guard let focusedDesk else { return }

        if focusedDesk.boards.isEmpty {
            deleteDesk(focusedDesk.id)
        } else {
            onWindowEffect?(.requestConfirmation(.deleteDesk(focusedDesk)))
        }
    }

    func confirmDeskDeletion(_ deskID: DeskID) { deleteDesk(deskID) }

    private func deleteDesk(_ deskID: DeskID) {
        storage.deskLifecycle.delete(
            deskID, presentedDeskID: presentedDeskID, isAvailable: { canPresentDesk?($0) ?? true },
            notify: deskLifecycleNotifications())
    }

    func renameFocusedDesk(to newLabel: String) {
        storage.deskUpdates.rename(presentedDeskID, to: newLabel) {
            onWindowEffect?(.dismissTemporaryPresentation)
            onWindowEffect?(.exitDenMode)
        }
    }

    func deskScrollOffset(for deskID: DeskID) -> CGFloat? {
        guard let desk = state.desks.first(where: { $0.id == deskID }) else { return nil }
        return desk.scrollOffsetX.map { CGFloat($0) }
    }

    func saveDeskScrollOffset(_ offset: CGFloat?, for deskID: DeskID) {
        storage.deskUpdates.saveScrollOffset(offset.map(Double.init), for: deskID)
    }

    func copyDeskID(_ deskID: DeskID, pasteboard: NSPasteboard? = nil) {
        let pasteboard = pasteboard ?? self.pasteboard
        guard state.desks.contains(where: { $0.id == deskID }) else { return }
        pasteboard.clearContents()
        pasteboard.setString(deskID.rawValue.uuidString.lowercased(), forType: .string)
        context.feedback.publish("Copied Desk ID.", severity: .success)
    }

    func deskLifecycleNotifications() -> (DeskLifecycle.Notice) -> Void {
        { [self] notice in
            switch notice {
            case .presentCreatedDesk(let id):
                boardNavigation.setFocusedDesk(id)
                onWindowEffect?(.dismissTemporaryPresentation)
                onWindowEffect?(.exitDenMode)
            case .didCreateDesk:
                storage.recordOperation(.deskCreated)
            case .willReplace(let boards):
                onWindowEffect?(.suppressBoardMutationAnimation)
                for board in boards { runtimes.disposeRuntime(for: board.id) }
            case .didReplace(let deskID, let boards):
                navigation.anchorJumpOriginBoardIDByDesk.removeValue(forKey: deskID)
                storage.invalidateReferences(toRemovedBoardIDs: Set(boards.map(\.id)))
                onWindowEffect?(.dismissTemporaryPresentation)
                onWindowEffect?(.exitDenMode)
            case .willDelete(let desk, let replacementID, let wasPresented):
                onWindowEffect?(.suppressBoardMutationAnimation)
                for board in desk.boards { runtimes.disposeRuntime(for: board.id) }
                if wasPresented { boardNavigation.setFocusedDesk(replacementID, autoPIP: false) }
            case .didDelete(let desk, let wasPresented):
                navigation.anchorJumpOriginBoardIDByDesk.removeValue(forKey: desk.id)
                storage.invalidateReferences(toRemovedBoardIDs: Set(desk.boards.map(\.id)))
                storage.invalidateReferences(toRemovedDeskID: desk.id)
                if wasPresented { onWindowEffect?(.exitDenMode) }
            }
        }
    }
}
