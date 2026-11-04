import ArgumentParser
import DenIPCProtocol
import Foundation

struct OverviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overview", abstract: "Show Desks vertically and Boards horizontally")

    @OptionGroup var options: CLIOptions
    @Flag(name: .shortAndLong, help: "Include full Desk and Board IDs in a numbered legend")
    var long = false
    @Flag(name: .long, help: "Output a text layout even when piped (mutually exclusive with --json)")
    var text = false

    func validate() throws {
        if text && options.isJSON {
            throw ValidationError("Specify only one of --text or --json")
        }
    }

    func run() throws {
        try DenIPCClient.execute(
            operation: .inspectDen(target: .automatic), options: options, showBoardIDs: long, forceText: text)
    }

    static func render(_ overview: DenIPCOverview, showIDs: Bool) -> String {
        var lines = ["Profile: \(label(overview.profile.name))"]
        var legend: [String] = []
        var number = 0

        func reference(id: String, kind: String, name: String) -> String {
            guard showIDs else { return "" }
            number += 1
            legend.append("\(number): \(kind) \(id) - \(label(name, limit: nil))")
            return "\(number): "
        }

        for desk in overview.desks {
            let prefix = reference(id: desk.id, kind: "desk", name: desk.label)
            lines.append("")
            lines.append("\(desk.isActive ? "*" : " ") \(prefix)\(label(desk.label))")
            let boards = desk.boards ?? []
            var groups: [String] = []
            for board in boards where board.targetBoardID == nil {
                let group = [board] + boards.filter { $0.targetBoardID == board.id }
                let cells = group.map { member in
                    let ref = reference(id: member.id, kind: member.type, name: member.label)
                    return "\(ref)\(member.type): \(label(member.label))\(member.isFocused ? " *" : "")"
                }
                groups.append("[\(cells.joined(separator: " | "))]")
            }
            lines.append("  " + (groups.isEmpty ? "(empty)" : groups.joined(separator: "  ")))
        }
        lines.append("\n* Current Desk / Focused Board in each Desk")
        if showIDs && !legend.isEmpty {
            lines.append("")
            lines.append(contentsOf: legend)
        }
        return lines.joined(separator: "\n")
    }

    private static func label(_ text: String, limit: Int? = 32) -> String {
        let clean = text.unicodeScalars.map { scalar -> String in
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return " "
            }
            switch scalar {
            case "[": return "("
            case "]": return ")"
            case "|": return "/"
            default: return String(scalar)
            }
        }.joined()
        guard let limit, clean.count > limit else { return clean }
        return String(clean.prefix(limit - 1)) + "…"
    }
}
