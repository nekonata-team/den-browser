import SwiftUI

struct DenDialogs: ViewModifier {
    let confirmDeskPresetDeletion: () -> Void

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
                "Replace \(store.deskPresetPendingReplacement?.label ?? "Desk Preset")?",
                isPresented: Binding(
                    get: { store.deskPresetPendingReplacement != nil },
                    set: { if !$0 { store.cancelDeskPresetReplacement() } })
            ) {
                Button("Replace Preset") {
                    store.confirmDeskPresetReplacement()
                    store.hideSaveDeskPresetPanel()
                }
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
                    confirmDeskPresetDeletion()
                }
                Button("Cancel", role: .cancel) { store.cancelDeskPresetDeletion() }
            } message: {
                Text("Existing Desks will not be affected.")
            }
    }
}
