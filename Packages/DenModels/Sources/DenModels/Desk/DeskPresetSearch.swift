public import DenDomain
import Foundation

public struct DeskPresetChoice: Equatable {
    public let selection: DeskPresetSelection
    public let label: String
    public let boards: [DeskPresetBoard]
    public let sourceLabel: String
    public init(selection: DeskPresetSelection, label: String, boards: [DeskPresetBoard], sourceLabel: String) {
        self.selection = selection
        self.label = label
        self.boards = boards
        self.sourceLabel = sourceLabel
    }
}

public enum DeskPresetSearch {
    public static func matchingChoices(
        allChoices: [DeskPresetChoice],
        query: String,
        allowsEmptyPreset: Bool
    ) -> [DeskPresetChoice] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allChoices }

        var ranked: [(choice: DeskPresetChoice, score: Int, index: Int)] = []
        for (index, choice) in allChoices.enumerated() {
            if let score = score(
                query: trimmedQuery,
                label: choice.label,
                boards: choice.boards
            ) {
                ranked.append((choice, score, index))
            }
        }
        ranked.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score
        }
        let matchingChoices = ranked.map(\.choice)
        guard allowsEmptyPreset else { return matchingChoices }
        return matchingChoices + [
            DeskPresetChoice(
                selection: .newDesk(label: trimmedQuery),
                label: "Create \"\(trimmedQuery)\"",
                boards: [],
                sourceLabel: "Empty Desk"
            )
        ]
    }

    public static func score(query: String, label: String, boards: [DeskPresetBoard]) -> Int? {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return 0 }

        let fields =
            [(label, 0)]
            + boards.flatMap { board -> [(String, Int)] in
                var fields = [(board.label, 1_000)]
                if let customLabel = board.customLabel {
                    fields.append((customLabel, 1_000))
                }
                return fields
            }
            + boards.compactMap { board in
                board.initialSheetURL?.host(percentEncoded: false).map { ($0, 2_000) }
            }
            + boards.compactMap { board in
                board.terminalWorkingDirectory.map { ($0, 2_000) }
            }
            + boards.compactMap { board in
                board.zellijSessionName.map { ($0, 2_000) }
            }
            + boards.compactMap { board in
                board.zmxSessionName.map { ($0, 2_000) }
            }

        var total = 0
        for token in tokens {
            guard
                let best = fields.compactMap({ field, penalty in
                    fuzzyScore(query: token, candidate: field).map { $0 + penalty }
                }).min()
            else { return nil }
            total += best
        }
        return total
    }

    private static func fuzzyScore(query: String, candidate: String) -> Int? {
        let query = normalized(query)
        let candidate = normalized(candidate)
        guard !query.isEmpty else { return 0 }
        guard !candidate.isEmpty else { return nil }

        if candidate.hasPrefix(query) {
            return candidate.count - query.count
        }
        if let range = candidate.range(of: query) {
            return 100 + candidate.distance(from: candidate.startIndex, to: range.lowerBound)
        }

        var searchStart = candidate.startIndex
        var gaps = 0
        for character in query {
            guard let index = candidate[searchStart...].firstIndex(of: character) else { return nil }
            gaps += candidate.distance(from: searchStart, to: index)
            searchStart = candidate.index(after: index)
        }
        return 200 + gaps + candidate.count - query.count
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }
}
