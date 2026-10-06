import Foundation

public enum DeskPresetTerminalSession: Codable, Equatable {
    case shell(workingDirectory: String)
    case zellij(sessionName: String?)
    case zmx(sessionName: String, rootSessionName: String?)

    private enum CodingKeys: String, CodingKey { case kind, workingDirectory, sessionName, rootSessionName }
    private enum Kind: String, Codable { case shell, zellij, zmx }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .shell:
            self = .shell(workingDirectory: try container.decode(String.self, forKey: .workingDirectory))
        case .zellij:
            self = .zellij(sessionName: try container.decodeIfPresent(String.self, forKey: .sessionName))
        case .zmx:
            self = .zmx(
                sessionName: try container.decode(String.self, forKey: .sessionName),
                rootSessionName: try container.decodeIfPresent(String.self, forKey: .rootSessionName))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shell(let workingDirectory):
            try container.encode(Kind.shell, forKey: .kind)
            try container.encode(workingDirectory, forKey: .workingDirectory)
        case .zellij(let sessionName):
            try container.encode(Kind.zellij, forKey: .kind)
            try container.encodeIfPresent(sessionName, forKey: .sessionName)
        case .zmx(let sessionName, let rootSessionName):
            try container.encode(Kind.zmx, forKey: .kind)
            try container.encode(sessionName, forKey: .sessionName)
            try container.encodeIfPresent(rootSessionName, forKey: .rootSessionName)
        }
    }
}
