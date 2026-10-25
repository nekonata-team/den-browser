import DenDomain
import DenInfrastructure
import Foundation

struct AgentShowMeScenario: DemoScenario {
    static let name = "agent-show-me"

    @MainActor
    func initialProfileURL(directory: URL) throws -> URL? {
        let terminalBoard = BoardState(
            label: "Terminal",
            width: 580,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        let desk = DeskState(
            label: "Design",
            boards: [terminalBoard],
            focusedBoardID: terminalBoard.id
        )
        let profile = PersistedProfile(
            profile: ProfileState(
                id: ProfileID(),
                name: "Demo",
                color: .blue,
                webProfileStore: .default
            ),
            den: DenState(
                desks: [desk],
                focusedDeskID: desk.id
            )
        )
        let profileFile = directory.appendingPathComponent("showme-initial-profile.json")
        let data = try JSONEncoder().encode(profile)
        try data.write(to: profileFile)
        return profileFile
    }

    func prepare(context: inout DemoContext) throws {
        print("Preparing: copying show-me HTML to /tmp/den-architecture.html…")
        let sourceURL = URL(fileURLWithPath: "Packages/DenDemo/Resources/show-me-den.html").standardizedFileURL
        let destURL = URL(fileURLWithPath: "/tmp/den-architecture.html")
        let data = try Data(contentsOf: sourceURL)
        try data.write(to: destURL)

        print("Preparing: waiting for Terminal Board to initialize…")
        try wait("Terminal Board", timeout: 20) {
            guard let headers = try? context.boardHeaders() else { return false }
            return !headers.isEmpty
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    func run(context: inout DemoContext) throws {
        let command = "den board web new file:///tmp/den-architecture.html --focus"

        print("Show-Me Step 1: Agent generates & opens visual explanation board with focus…")
        let start = context.timestamp()
        try context.peek([
            "type",
            command,
            "--delay", "12",
            "--accept-dispatched",
        ])
        try context.peek(["press", "Return"])
        context.addCaption(
            "Visual Explanations · Instant diagram boards via CLI",
            from: start,
            to: start + 3200
        )

        print("Show-Me Step 2: Waiting for diagram Web Board to open & focus…")
        try wait("Diagram Board to appear", timeout: 15) {
            guard let headers = try? context.boardHeaders() else { return false }
            return headers.count == 2
        }
        Thread.sleep(forTimeInterval: 3.0)
    }
}
