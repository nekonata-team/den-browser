import SwiftUI

struct DenDialogs: ViewModifier {
    @Environment(DenStore.self) private var store

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete \(store.deskPendingDeletion?.label ?? "Desk")?",
                isPresented: Binding(
                    get: { store.deskPendingDeletion != nil },
                    set: { if !$0 { store.cancelDeskDeletion() } })
            ) {
                Button("Delete Desk", role: .destructive) {
                    store.confirmDeskDeletion()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    store.cancelDeskDeletion()
                }
            } message: {
                let boardCount = store.deskPendingDeletion?.boards.count ?? 0
                Text(
                    boardCount == 1
                        ? "Its Board and Sheet Stack will be permanently deleted."
                        : "Its \(boardCount) Boards and their Sheet Stacks will be permanently deleted."
                )
            }
            .confirmationDialog(
                "Replace \(store.deskPendingReplacement?.originalLabel ?? "Desk")?",
                isPresented: Binding(
                    get: { store.deskPendingReplacement != nil },
                    set: { if !$0 { store.cancelDeskReplacement() } })
            ) {
                Button("Replace Desk", role: .destructive) {
                    store.confirmDeskReplacement()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    store.cancelDeskReplacement()
                }
            } message: {
                let boardCount = store.deskPendingReplacement?.originalBoardCount ?? 0
                let presetLabel = store.deskPendingReplacement?.presetLabel ?? "selected"
                Text(
                    boardCount == 1
                        ? "Its Board and live Sheet state will be removed and replaced with the \(presetLabel) arrangement."
                        : "Its \(boardCount) Boards and live Sheet state will be removed and replaced with the \(presetLabel) arrangement."
                )
            }
            .confirmationDialog(
                "Replace \(store.deskPresetPendingReplacement?.label ?? "Desk Preset")?",
                isPresented: Binding(
                    get: { store.deskPresetPendingReplacement != nil },
                    set: { if !$0 { store.cancelDeskPresetReplacement() } })
            ) {
                Button("Replace Preset") {
                    store.confirmDeskPresetReplacement()
                    store.hideSaveDeskPresetPanel()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { store.cancelDeskPresetReplacement() }
            } message: {
                Text("Existing Desks will not be affected.")
            }
            .confirmationDialog(
                "Reset Den?",
                isPresented: Binding(
                    get: { store.isResetDenPending },
                    set: { if !$0 { store.cancelResetDen() } })
            ) {
                Button("Reset Den", role: .destructive) {
                    store.confirmResetDen()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    store.cancelResetDen()
                }
            } message: {
                Text("All Desks, Boards, and Sheet Stacks in this Den will be permanently deleted.")
            }
            .confirmationDialog(
                "Delete \(store.deskPresetPendingDeletion?.label ?? "Desk Preset")?",
                isPresented: Binding(
                    get: { store.deskPresetPendingDeletion != nil },
                    set: { if !$0 { store.cancelDeskPresetDeletion() } })
            ) {
                Button("Delete Preset", role: .destructive) {
                    store.confirmDeskPresetDeletion()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { store.cancelDeskPresetDeletion() }
            } message: {
                Text("Existing Desks will not be affected.")
            }
            .confirmationDialog(
                "Discard all Drawer items?",
                isPresented: Binding(
                    get: { store.drawerPendingDeletionCount != nil },
                    set: { if !$0 { store.cancelDrawerClear() } })
            ) {
                Button("Discard All", role: .destructive) {
                    store.confirmDrawerClear()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    store.cancelDrawerClear()
                }
            } message: {
                let count = store.drawerPendingDeletionCount ?? 0
                Text("All \(count) Drawer items will be discarded.")
            }
            .confirmationDialog(
                "Clear all Notifications?",
                isPresented: Binding(
                    get: { store.notificationPendingDeletionCount != nil },
                    set: { if !$0 { store.cancelNotificationClear() } })
            ) {
                Button("Clear All", role: .destructive) {
                    store.confirmNotificationClear()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    store.cancelNotificationClear()
                }
            } message: {
                let count = store.notificationPendingDeletionCount ?? 0
                Text("All \(count) Notifications will be removed from this app run.")
            }
    }
}
