import DenApplication
import DenDomain
import DenPresentationModels
import SwiftUI

struct DenDialogs: ViewModifier {
    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel

    private var pendingDeskDeletion: DeskState? {
        guard case .deleteDesk(let desk)? = windowModel.pendingConfirmation else { return nil }
        return desk
    }

    private var pendingDeskReplacement: PendingDeskReplacement? {
        guard case .replaceDesk(let replacement)? = windowModel.pendingConfirmation else { return nil }
        return replacement
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "End \(windowModel.zmxSessionPendingEnd ?? "zmx Session")?",
                isPresented: Binding(
                    get: { windowModel.zmxSessionPendingEnd != nil },
                    set: { if !$0 { windowModel.cancelConfirmation() } })
            ) {
                Button("End Session", role: .destructive) {
                    windowModel.confirmZmxSessionEnd()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { windowModel.cancelConfirmation() }
            } message: {
                Text(
                    "This ends the zmx Session and closes its attached Boards. Child Sessions remain running. Restoring a Board does not restore the running processes."
                )
            }
            .confirmationDialog(
                "Delete \(pendingDeskDeletion?.label ?? "Desk")?",
                isPresented: Binding(
                    get: { pendingDeskDeletion != nil },
                    set: { if !$0 { windowModel.cancelConfirmation() } })
            ) {
                Button("Delete Desk", role: .destructive) {
                    windowModel.confirmDeskDeletion()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    windowModel.cancelConfirmation()
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
                    set: { if !$0 { windowModel.cancelConfirmation() } })
            ) {
                Button("Replace Desk", role: .destructive) {
                    windowModel.confirmDeskReplacement()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    windowModel.cancelConfirmation()
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
                "Replace \(windowModel.deskPresetPendingReplacement?.label ?? "Desk Preset")?",
                isPresented: Binding(
                    get: { windowModel.deskPresetPendingReplacement != nil },
                    set: { if !$0 { windowModel.cancelDeskPresetReplacement() } })
            ) {
                Button("Replace Preset") {
                    windowModel.confirmDeskPresetReplacement()
                    windowModel.hideSaveDeskPresetPanel()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { windowModel.cancelDeskPresetReplacement() }
            } message: {
                Text("Existing Desks will not be affected.")
            }
            .confirmationDialog(
                "Replace \(windowModel.essentialPendingReplacement?.name ?? "Essential")?",
                isPresented: Binding(
                    get: { windowModel.essentialPendingReplacement != nil },
                    set: { if !$0 { windowModel.cancelEssentialReplacement() } })
            ) {
                Button("Replace Essential") {
                    windowModel.confirmEssentialReplacement()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { windowModel.cancelEssentialReplacement() }
            } message: {
                let key = windowModel.essentialPendingReplacement?.displayKey ?? ""
                Text(
                    "The name and input assigned to key '\(key)' will be replaced. Existing Boards will not be affected."
                )
            }
            .confirmationDialog(
                "Reset Den?",
                isPresented: Binding(
                    get: { windowModel.isResetDenPending },
                    set: { if !$0 { windowModel.cancelResetDen() } })
            ) {
                Button("Reset Den", role: .destructive) {
                    windowModel.confirmResetDen()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    windowModel.cancelResetDen()
                }
            } message: {
                Text("All Desks, Boards, and Sheet Stacks in this Den will be permanently deleted.")
            }
            .confirmationDialog(
                "Delete \(windowModel.deskPresetPendingDeletion?.label ?? "Desk Preset")?",
                isPresented: Binding(
                    get: { windowModel.deskPresetPendingDeletion != nil },
                    set: { if !$0 { windowModel.cancelDeskPresetDeletion() } })
            ) {
                Button("Delete Preset", role: .destructive) {
                    windowModel.confirmDeskPresetDeletion()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { windowModel.cancelDeskPresetDeletion() }
            } message: {
                Text("Existing Desks will not be affected.")
            }
            .confirmationDialog(
                "Discard all Drawer items?",
                isPresented: Binding(
                    get: { windowModel.drawerPendingDeletionCount != nil },
                    set: { if !$0 { windowModel.cancelDrawerClear() } })
            ) {
                Button("Discard All", role: .destructive) {
                    windowModel.confirmDrawerClear()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    windowModel.cancelDrawerClear()
                }
            } message: {
                let count = windowModel.drawerPendingDeletionCount ?? 0
                Text("All \(count) Drawer items will be discarded.")
            }
            .confirmationDialog(
                "Clear all Notifications?",
                isPresented: Binding(
                    get: { windowModel.notificationPendingDeletionCount != nil },
                    set: { if !$0 { windowModel.cancelNotificationClear() } })
            ) {
                Button("Clear All", role: .destructive) {
                    windowModel.confirmNotificationClear()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    windowModel.cancelNotificationClear()
                }
            } message: {
                let count = windowModel.notificationPendingDeletionCount ?? 0
                Text("All \(count) Notifications will be removed from this app run.")
            }
    }
}
