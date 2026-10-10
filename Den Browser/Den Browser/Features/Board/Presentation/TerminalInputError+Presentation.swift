import DenApplication

extension TerminalInputError {
    var message: String {
        switch self {
        case .missingDirectory(let path): "Terminal directory does not exist: \(path)"
        }
    }
}
