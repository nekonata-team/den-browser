import DenDomain

enum TerminalLaunchCommand {
    static func make(
        for kind: BoardKind,
        zellijClient: ZellijClient,
        zmxClient: ZmxClient
    ) -> String? {
        guard case .terminal(let terminal) = kind else { return nil }
        return switch terminal {
        case .shell:
            nil
        case .zellij(let zellij):
            zellijClient.launchCommand(sessionName: zellij.sessionName)
        case .zmx(let zmx):
            zmxClient.launchCommand(sessionName: zmx.sessionName, rootSessionName: zmx.rootSessionName)
        }
    }
}
