import SwiftUI

struct DenDialogs: ViewModifier {
    @Environment(DenStore.self) private var store
    @Environment(DenViewModel.self) private var viewModel

    private var pendingDeskDeletion: DeskState? {
        guard case .deleteDesk(let desk)? = viewModel.pendingConfirmation else { return nil }
        return desk
    }

    private var pendingDeskReplacement: PendingDeskReplacement? {
        guard case .replaceDesk(let replacement)? = viewModel.pendingConfirmation else { return nil }
        return replacement
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete \(pendingDeskDeletion?.label ?? "Desk")?",
                isPresented: Binding(
                    get: { pendingDeskDeletion != nil },
                    set: { if !$0 { viewModel.cancelConfirmation() } })
            ) {
                Button("Delete Desk", role: .destructive) {
                    viewModel.confirmDeskDeletion()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    viewModel.cancelConfirmation()
                }
            } message: {
                let boardCount = pendingDeskDeletion?.boards.count ?? 0
                Text(
                    boardCount == 1
                        ? "Its Board and Sheet Stack will be permanently deleted."
                        : "Its \(boardCount) Boards and their Sheet Stacks will be permanently deleted."
                )
            }
            .confirmationDialog(
                "Replace \(pendingDeskReplacement?.originalLabel ?? "Desk")?",
                isPresented: Binding(
                    get: { pendingDeskReplacement != nil },
                    set: { if !$0 { viewModel.cancelConfirmation() } })
            ) {
                Button("Replace Desk", role: .destructive) {
                    viewModel.confirmDeskReplacement()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    viewModel.cancelConfirmation()
                }
            } message: {
                let boardCount = pendingDeskReplacement?.originalBoardCount ?? 0
                let presetLabel = pendingDeskReplacement?.presetLabel ?? "selected"
                Text(
                    boardCount == 1
                        ? "Its Board and live Sheet state will be removed and replaced with the \(presetLabel) arrangement."
                        : "Its \(boardCount) Boards and live Sheet state will be removed and replaced with the \(presetLabel) arrangement."
                )
            }
            .confirmationDialog(
                "Replace \(viewModel.deskPresetPendingReplacement?.label ?? "Desk Preset")?",
                isPresented: Binding(
                    get: { viewModel.deskPresetPendingReplacement != nil },
                    set: { if !$0 { viewModel.cancelDeskPresetReplacement() } })
            ) {
                Button("Replace Preset") {
                    viewModel.confirmDeskPresetReplacement()
                    viewModel.hideSaveDeskPresetPanel()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { viewModel.cancelDeskPresetReplacement() }
            } message: {
                Text("Existing Desks will not be affected.")
            }
            .confirmationDialog(
                "Reset Den?",
                isPresented: Binding(
                    get: { viewModel.isResetDenPending },
                    set: { if !$0 { viewModel.cancelResetDen() } })
            ) {
                Button("Reset Den", role: .destructive) {
                    viewModel.confirmResetDen()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    viewModel.cancelResetDen()
                }
            } message: {
                Text("All Desks, Boards, and Sheet Stacks in this Den will be permanently deleted.")
            }
            .confirmationDialog(
                "Delete \(viewModel.deskPresetPendingDeletion?.label ?? "Desk Preset")?",
                isPresented: Binding(
                    get: { viewModel.deskPresetPendingDeletion != nil },
                    set: { if !$0 { viewModel.cancelDeskPresetDeletion() } })
            ) {
                Button("Delete Preset", role: .destructive) {
                    viewModel.confirmDeskPresetDeletion()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { viewModel.cancelDeskPresetDeletion() }
            } message: {
                Text("Existing Desks will not be affected.")
            }
            .confirmationDialog(
                "Discard all Drawer items?",
                isPresented: Binding(
                    get: { viewModel.drawerPendingDeletionCount != nil },
                    set: { if !$0 { viewModel.cancelDrawerClear() } })
            ) {
                Button("Discard All", role: .destructive) {
                    viewModel.confirmDrawerClear()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    viewModel.cancelDrawerClear()
                }
            } message: {
                let count = viewModel.drawerPendingDeletionCount ?? 0
                Text("All \(count) Drawer items will be discarded.")
            }
            .confirmationDialog(
                "Clear all Notifications?",
                isPresented: Binding(
                    get: { viewModel.notificationPendingDeletionCount != nil },
                    set: { if !$0 { viewModel.cancelNotificationClear() } })
            ) {
                Button("Clear All", role: .destructive) {
                    viewModel.confirmNotificationClear()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    viewModel.cancelNotificationClear()
                }
            } message: {
                let count = viewModel.notificationPendingDeletionCount ?? 0
                Text("All \(count) Notifications will be removed from this app run.")
            }
    }
}
