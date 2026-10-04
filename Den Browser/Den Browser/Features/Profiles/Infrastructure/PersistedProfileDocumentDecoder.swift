import Foundation

enum PersistedProfileDocumentDecoder {
    private struct SchemaVersion: Decodable {
        var schemaVersion: Int
    }

    static func decode(_ data: Data) throws -> PersistedProfile {
        let decoder = JSONDecoder()
        let version = try decoder.decode(SchemaVersion.self, from: data).schemaVersion
        guard (1...PersistedProfile.currentSchemaVersion).contains(version) else {
            throw ProfilePersistenceError.unsupportedPersistedProfileSchema(version)
        }

        guard version < PersistedProfile.currentSchemaVersion else {
            return try decoder.decode(PersistedProfile.self, from: data)
        }

        let migratedData = try migrate(data, from: version)
        return try decoder.decode(PersistedProfile.self, from: migratedData)
    }

    private static func migrate(_ data: Data, from version: Int) throws -> Data {
        guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "Persisted Profile document must be a JSON object."))
        }

        migrateBoards(in: &document, from: version)
        migrateDeskPresets(in: &document, from: version)
        document["schemaVersion"] = PersistedProfile.currentSchemaVersion
        return try JSONSerialization.data(withJSONObject: document)
    }

    private static func migrateBoards(in document: inout [String: Any], from version: Int) {
        guard
            var den = document["den"] as? [String: Any],
            var desks = den["desks"] as? [[String: Any]]
        else { return }

        for deskIndex in desks.indices {
            guard var boards = desks[deskIndex]["boards"] as? [[String: Any]] else { continue }
            for boardIndex in boards.indices {
                migrateBoard(&boards[boardIndex], from: version)
            }
            desks[deskIndex]["boards"] = boards
        }

        den["desks"] = desks
        document["den"] = den
    }

    private static func migrateBoard(_ board: inout [String: Any], from version: Int) {
        var content = board["content"] as? [String: Any]
        if content == nil, version == 1 {
            content = ["kind": "web"]
            for key in ["currentSheetURL", "firstSheetURL", "sheetNavigationPaused"] {
                if let value = board.removeValue(forKey: key) {
                    content?[key] = value
                }
            }
        }
        guard var content else { return }

        if version == 2 {
            switch content["kind"] as? String {
            case "terminal":
                if content["session"] == nil,
                    let workingDirectory = content.removeValue(forKey: "workingDirectory")
                {
                    content["session"] = ["kind": "shell", "workingDirectory": workingDirectory]
                }
            case .some("zellij"), .some("zmx"):
                let session = content
                content = ["kind": "terminal", "session": session]
            default:
                break
            }
        }

        if content["kind"] as? String == "web",
            let paused = board.removeValue(forKey: "sheetNavigationPaused")
        {
            content["sheetNavigationPaused"] = paused
        }
        board.removeValue(forKey: "currentSheetURL")
        board.removeValue(forKey: "firstSheetURL")
        board.removeValue(forKey: "sheetNavigationPaused")
        board["content"] = content
    }

    private static func migrateDeskPresets(in document: inout [String: Any], from version: Int) {
        guard var presets = document["deskPresets"] as? [[String: Any]] else { return }

        for presetIndex in presets.indices {
            guard var boards = presets[presetIndex]["boards"] as? [[String: Any]] else { continue }
            for boardIndex in boards.indices {
                migrateDeskPresetBoard(&boards[boardIndex], from: version)
            }
            presets[presetIndex]["boards"] = boards
        }

        document["deskPresets"] = presets
    }

    private static func migrateDeskPresetBoard(_ board: inout [String: Any], from version: Int) {
        var content = board["content"] as? [String: Any]
        if content == nil, version == 1 {
            content = ["kind": "web"]
            if let initialSheetURL = board.removeValue(forKey: "initialSheetURL") {
                content?["initialSheetURL"] = initialSheetURL
            }
            board["content"] = content
            return
        }
        guard var content, version == 2 else { return }

        switch content["kind"] as? String {
        case "terminal":
            if content["session"] == nil,
                let workingDirectory = content.removeValue(forKey: "workingDirectory")
            {
                content["session"] = ["kind": "shell", "workingDirectory": workingDirectory]
            }
        case .some("zellij"), .some("zmx"):
            let session = content
            content = ["kind": "terminal", "session": session]
        default:
            break
        }

        board["content"] = content
    }
}
