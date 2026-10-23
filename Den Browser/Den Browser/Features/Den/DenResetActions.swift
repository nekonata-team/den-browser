import DenApplication
import DenDomain
import DenModels
import Foundation

@MainActor
final class DenResetActions {
    private let context: WindowNativeContext
    private var runtimes: BoardRuntimeAccess { context.runtimes }
    private var storage: DenProfileResources { context.storage }
    private var preferences: AppPreferences { context.configuration.preferences }
    private var navigation: WindowNavigationBindings { context.navigation }
    private var onWillResetDen: (() -> Void)? { context.onWillResetDen }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }

    init(context: WindowNativeContext) {
        self.context = context
    }

    func resetDen() {
        storage.denReset.perform { notice in
            switch notice {
            case .prepare:
                onWillResetDen?()
                runtimes.releaseRuntimes()
                runtimes.releaseWindowResources()
            case .cancelDrag(.board):
                onWindowEffect?(.cancelBoardDrag)
            case .cancelDrag(.desk):
                onWindowEffect?(.cancelDeskDrag)
            case .stateReplaced(let deskID):
                navigation.replacePresentedDesk(deskID)
                preferences.setBoardRailPresented(false)
            case .clearInputRequests:
                onWindowEffect?(.clearBoardInputRequests)
            case .clearWindowReferences:
                navigation.clearHistory()
            case .finished:
                onWindowEffect?(.resetPresentation)
                context.feedback.publish("Reset Den completed.", severity: .success)
            }
        }
    }
}
