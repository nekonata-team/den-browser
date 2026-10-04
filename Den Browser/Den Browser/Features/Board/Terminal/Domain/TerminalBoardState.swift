import Foundation

enum TerminalBoardState: Codable, Equatable {
    case shell(workingDirectory: String)
    case zellij(ZellijBoardState)
    case zmx(ZmxBoardState)

    var workingDirectory: String? {
        switch self {
        case .shell(let workingDirectory): workingDirectory
        case .zmx(let zmx): zmx.workingDirectory
        case .zellij: nil
        }
    }

    var zellijSessionName: String? {
        guard case .zellij(let zellij) = self else { return nil }
        return zellij.sessionName
    }

    var zmxSessionName: String? {
        guard case .zmx(let zmx) = self else { return nil }
        return zmx.sessionName
    }

    var zmxRootSessionName: String? {
        guard case .zmx(let zmx) = self else { return nil }
        return zmx.rootSessionName
    }

    private enum CodingKeys: String, CodingKey {
        case kind, workingDirectory, sessionName, rootSessionName
    }
    private enum Kind: String, Codable { case shell, zellij, zmx }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .shell:
            self = .shell(workingDirectory: try container.decode(String.self, forKey: .workingDirectory))
        case .zellij:
            self = .zellij(
                ZellijBoardState(
                    sessionName: try container.decodeIfPresent(String.self, forKey: .sessionName)))
        case .zmx:
            self = .zmx(
                ZmxBoardState(
                    sessionName: try container.decode(String.self, forKey: .sessionName),
                    workingDirectory: try container.decode(String.self, forKey: .workingDirectory),
                    rootSessionName: try container.decodeIfPresent(String.self, forKey: .rootSessionName)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shell(let workingDirectory):
            try container.encode(Kind.shell, forKey: .kind)
            try container.encode(workingDirectory, forKey: .workingDirectory)
        case .zellij(let zellij):
            try container.encode(Kind.zellij, forKey: .kind)
            try container.encodeIfPresent(zellij.sessionName, forKey: .sessionName)
        case .zmx(let zmx):
            try container.encode(Kind.zmx, forKey: .kind)
            try container.encode(zmx.sessionName, forKey: .sessionName)
            try container.encode(zmx.workingDirectory, forKey: .workingDirectory)
            try container.encodeIfPresent(zmx.rootSessionName, forKey: .rootSessionName)
        }
    }
}

struct ZellijBoardState: Codable, Equatable {
    var sessionName: String?
}

struct ZmxBoardState: Codable, Equatable {
    var sessionName: String
    var workingDirectory: String
    var rootSessionName: String?

    init(sessionName: String, workingDirectory: String, rootSessionName: String? = nil) {
        self.sessionName = sessionName
        self.workingDirectory = workingDirectory
        self.rootSessionName = rootSessionName
    }
}
