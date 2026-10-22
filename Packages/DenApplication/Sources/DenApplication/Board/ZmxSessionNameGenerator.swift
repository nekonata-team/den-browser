import Foundation

public nonisolated enum ZmxSessionNameGenerator {
    public static func normalizedSuffix(_ suffix: String) -> String {
        suffix.filter { character in
            character.isASCII
                && (character.isLetter || character.isNumber || "-_".contains(character) || character == ".")
        }
    }

    public static func nextName(rootSessionName: String, suffix: String, occupiedNames: Set<String>) -> String {
        let cleanSuffix = normalizedSuffix(suffix)
        if cleanSuffix.isEmpty {
            var number = 2
            var candidate = "\(rootSessionName)-\(number)"
            while occupiedNames.contains(candidate) {
                number += 1
                candidate = "\(rootSessionName)-\(number)"
            }
            return candidate
        }

        let baseName = "\(rootSessionName)-\(cleanSuffix)"
        var candidate = baseName
        var number = 2
        while occupiedNames.contains(candidate) {
            candidate = "\(baseName)-\(number)"
            number += 1
        }
        return candidate
    }
}
