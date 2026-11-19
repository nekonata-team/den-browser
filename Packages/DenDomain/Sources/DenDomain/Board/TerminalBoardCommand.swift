public enum TerminalBoardCommand {
    public static let terminal = [":terminal", ":term"]
    public static let zellij = [":zellij", ":zj"]
    public static let zmx = [":zmx", ":x"]

    static func names(for input: String) -> [String] {
        guard let name = input.split(maxSplits: 1, whereSeparator: \.isWhitespace).first else { return [] }
        return [terminal, zellij, zmx].first { $0.contains(String(name)) } ?? []
    }
}
