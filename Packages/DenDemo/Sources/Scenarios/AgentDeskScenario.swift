import DenDomain
import DenInfrastructure
import Foundation

struct AgentDeskScenario: DemoScenario {
    static let name = "agent-desk"

    nonisolated(unsafe) static var researchDeskID = DeskID()

    @MainActor
    func initialProfileURL(directory: URL) throws -> URL? {
        let terminalBoard = BoardState(
            label: "Terminal",
            width: 680,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        let mainDesk = DeskState(
            label: "Main",
            boards: [terminalBoard],
            focusedBoardID: terminalBoard.id
        )
        let researchDesk = DeskState(
            id: Self.researchDeskID,
            label: "Research",
            boards: []
        )
        let profile = PersistedProfile(
            profile: ProfileState(
                id: ProfileID(),
                name: "Demo",
                color: .blue,
                webProfileStore: .default
            ),
            den: DenState(
                desks: [mainDesk, researchDesk],
                focusedDeskID: mainDesk.id
            )
        )
        let profileFile = directory.appendingPathComponent("desk-initial-profile.json")
        let data = try JSONEncoder().encode(profile)
        try data.write(to: profileFile)
        return profileFile
    }

    func prepare(context: inout DemoContext) throws {
        print("Preparing: waiting for Terminal Board to initialize…")
        try wait("Terminal Board", timeout: 20) {
            guard let headers = try? context.boardHeaders() else { return false }
            return !headers.isEmpty
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    func run(context: inout DemoContext) throws {
        let urls = [
            "https://en.wikipedia.org/wiki/Software_agent",
            "https://en.wikipedia.org/wiki/Autonomous_agent",
            "https://en.wikipedia.org/wiki/Intelligent_agent",
        ]
        let deskUUID = Self.researchDeskID.rawValue.uuidString

        print("Desk Step 1: Listing available desks…")
        let listStart = context.timestamp()
        try context.peek(["type", "den desk list", "--delay", "25", "--accept-dispatched"])
        try context.peek(["press", "Return"])
        context.addCaption("Discover workspace Desks via CLI", from: listStart, to: listStart + 2200)
        Thread.sleep(forTimeInterval: 1.8)

        print("Desk Step 2: Deploying 3 research boards to background Desk…")
        let deployStart = context.timestamp()
        context.addCaption(
            "Deploy to background Desk · Human context stays clean",
            from: deployStart,
            to: deployStart + 4000
        )
        for (index, url) in urls.enumerated() {
            try context.peek([
                "type",
                "den board web new \(url) --desk \(deskUUID)",
                "--delay", "10",
                "--accept-dispatched",
            ])
            try context.peek(["press", "Return"])
            Thread.sleep(forTimeInterval: index == urls.count - 1 ? 1.5 : 0.8)
        }

        print("Desk Step 3: Clicking to switch to Research Desk…")
        let switchStart = context.timestamp()
        context.addCaption("Click Desk tab to inspect agent's work", from: switchStart, to: switchStart + 2200)
        try context.click("2. Research")
        try wait("Research Desk", timeout: 10) {
            guard let headers = try? context.boardHeaders() else { return false }
            return !headers.isEmpty
        }
        Thread.sleep(forTimeInterval: 1.2)

        print("Desk Step 4: Focusing adjacent research board…")
        let focusStart = context.timestamp()
        context.addCaption("Glide across parallel research boards", from: focusStart, to: focusStart + 2500)
        let headers = try context.boardHeaders()
        let sorted = headers.values.sorted { $0.minX < $1.minX }
        if sorted.count >= 2 {
            let nextBoard = sorted[1]
            let position = "\(Int(nextBoard.midX)),\(Int(nextBoard.midY))"
            try context.peek(["move", "--at", position, "--global", "--smooth", "--duration", "600ms"])
            try context.peek(["click", "--at", position, "--global"])
            Thread.sleep(forTimeInterval: 2.5)
        } else if let only = sorted.first {
            let position = "\(Int(only.midX)),\(Int(only.midY))"
            try context.peek(["move", "--at", position, "--global", "--smooth", "--duration", "600ms"])
            try context.peek(["click", "--at", position, "--global"])
            Thread.sleep(forTimeInterval: 2.5)
        }
    }
}
