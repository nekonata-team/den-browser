import AppKit
import DenApplication
import DenDomain
import DenModels

extension TerminalRuntime {
    static func drawerEvents(
        itemID: UUID, storage: DenProfileResources, connection: RuntimeWindowConnection
    ) -> Events {
        .init(
            onClose: { [weak storage] in
                storage?.windowConnections.allObjects.compactMap(\.drawer).first?.discardDrawerItem(itemID)
            },
            onFocus: { [connection] in
                guard connection.windowResources?.drawerItemID == itemID else { return }
                connection.onWindowEffect?(.exitDenMode)
            },
            onWorkingDirectoryChange: { [weak storage] in
                storage?.drawerItems.updateTerminal(itemID, workingDirectory: $0)
            },
            onTitleChange: { [weak storage] in storage?.drawerItems.updateTerminal(itemID, title: $0) },
            onOpenURL: { [weak storage, connection] rawURL in
                guard let item = storage?.state.drawerItems.first(where: { $0.id == itemID }),
                    let link = TerminalLinkResolver.resolve(
                        rawURL,
                        relativeTo: item.terminal?.workingDirectory
                            ?? FileManager.default.homeDirectoryForCurrentUser.path)
                else { return }
                switch link {
                case .localFile(let url): _ = NSWorkspace.shared.open(url)
                case .web(let url): connection.drawer?.keepInDrawer(url, opensDrawer: false)
                }
            },
            onNotification: { [weak storage, connection] title, body in
                let feedback = connection.feedback ?? storage?.windowConnections.allObjects.compactMap(\.feedback).first
                feedback?.publish(title: title, body: body, target: .drawerItem(itemID))
            })
    }
}
