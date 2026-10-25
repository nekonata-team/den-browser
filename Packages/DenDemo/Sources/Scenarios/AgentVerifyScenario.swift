import DenDomain
import DenInfrastructure
import Foundation

struct AgentVerifyScenario: DemoScenario {
    static let name = "agent-verify"

    @MainActor
    func initialProfileURL(directory: URL) throws -> URL? {
        let htmlFile = URL(fileURLWithPath: "Packages/DenDemo/Resources/demo-app.html").standardizedFileURL
        guard FileManager.default.fileExists(atPath: htmlFile.path) else {
            throw DemoError(description: "demo-app.html not found at \(htmlFile.path)")
        }

        let terminalBoard = BoardState(
            label: "Terminal",
            width: 580,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        let webBoard = BoardState(
            label: "Task Verification",
            width: 580,
            currentSheetURL: htmlFile
        )
        let desk = DeskState(
            label: "Agent",
            boards: [terminalBoard, webBoard],
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
        let profileFile = directory.appendingPathComponent("agent-initial-profile.json")
        let data = try JSONEncoder().encode(profile)
        try data.write(to: profileFile)
        return profileFile
    }

    func prepare(context: inout DemoContext) throws {
        print("Preparing: waiting for live preview to load…")
        try wait("the preview page", timeout: 30) {
            try context.tree().contains("Task Verification")
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    func run(context: inout DemoContext) throws {
        print("Agent Step 1: Taking semantic snapshot…")
        let snapStart = context.timestamp()
        try context.peek(["type", "den board web snapshot", "--delay", "25", "--accept-dispatched"])
        try context.peek(["press", "Return"])
        context.addCaption("Zero-Config · Compact Semantic Snapshot", from: snapStart, to: snapStart + 2600)
        Thread.sleep(forTimeInterval: 2.3)

        print("Agent Step 2: Clicking checkbox @e1…")
        let click1Start = context.timestamp()
        try context.peek(["type", "den board web click @e1", "--delay", "25", "--accept-dispatched"])
        try context.peek(["press", "Return"])
        context.addCaption("Agent drives adjacent Web Board (@e1)", from: click1Start, to: click1Start + 2000)
        Thread.sleep(forTimeInterval: 1.8)

        print("Agent Step 3: Clicking checkbox @e2…")
        let click2Start = context.timestamp()
        try context.peek(["type", "den board web click @e2", "--delay", "25", "--accept-dispatched"])
        try context.peek(["press", "Return"])
        context.addCaption("Automatic task verification (@e2)", from: click2Start, to: click2Start + 2000)
        Thread.sleep(forTimeInterval: 1.8)

        print("Agent Step 4: Clicking button @e3…")
        let buttonStart = context.timestamp()
        try context.peek(["type", "den board web click @e3", "--delay", "25", "--accept-dispatched"])
        try context.peek(["press", "Return"])
        context.addCaption("Immediate visual feedback side-by-side", from: buttonStart, to: buttonStart + 2500)
        Thread.sleep(forTimeInterval: 2.3)
    }
}
