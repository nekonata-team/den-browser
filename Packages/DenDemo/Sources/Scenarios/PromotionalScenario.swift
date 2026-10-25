import Foundation

struct PromotionalScenario: DemoScenario {
    static let name = "promotional"

    func run(context: inout DemoContext) throws {
        print("Research: collecting product and source pages…")
        try context.openBoard("https://den.nekonata.dev", using: "Open Board")
        try wait("the product page", timeout: 30) { try context.tree().contains("Web and terminal work") }
        Thread.sleep(forTimeInterval: 0.5)
        try context.openBoard("https://github.com/nekonata-team/den-browser", using: "Open Board at End of Desk")
        try wait("the repository page", timeout: 30) { try context.tree().contains("GitHub") }
        Thread.sleep(forTimeInterval: 0.5)

        print("Build: creating a separate Desk…")
        try context.click("New Desk")
        try wait("the Desk preset picker") { try context.tree().contains("Empty") }
        try context.peek(["type", "Build", "--delay", "40", "--accept-dispatched"])
        try context.click("Create \"Build\"")
        try wait("the Build Desk") { try context.tree().contains("2. Build") }

        print("Opening Terminal Board…")
        try context.openBoard(":terminal", using: "Open Board")
        Thread.sleep(forTimeInterval: 0.3)
        try context.peek(["type", "echo hello", "--delay", "25", "--accept-dispatched"])
        try context.peek(["press", "Return"])
        Thread.sleep(forTimeInterval: 0.5)

        print("Build: duplicating Terminal from the Header menu…")
        let originalHeaders = try context.boardHeaders()
        guard originalHeaders.count == 1, let originalHeader = originalHeaders.keys.first else {
            throw DemoError(description: "Expected one Terminal Board before duplication")
        }
        try context.click(originalHeader, right: true)
        try wait("the Terminal Header menu") { try context.tree().contains("Duplicate Terminal Board") }
        Thread.sleep(forTimeInterval: 0.4)
        try context.click("Duplicate Terminal Board")
        try wait("the duplicated Terminal Board") {
            let headers = try context.boardHeaders()
            let added = Set(headers.keys).subtracting(originalHeaders.keys)
            return headers.count == 2 && added.count == 1
        }
        Thread.sleep(forTimeInterval: 0.3)

        print("Gemini: opening a three-Board preset…")
        try context.click("New Desk")
        try wait("the Desk preset picker") { try context.tree().contains("Empty") }
        try context.click("Gemini")
        try context.click("Create")
        try wait("the Gemini Desk") { try context.tree().contains("3. Gemini") }
        Thread.sleep(forTimeInterval: 0.8)

        print("Gemini: navigating right, right, left in Den Mode…")
        try context.peek(["press", "ctrl+comma"])
        try wait("Den Mode") { try context.tree().contains("DEN MODE") }
        Thread.sleep(forTimeInterval: 0.3)
        let navigationStart = context.timestamp()
        for key in ["right", "right", "left"] {
            try context.peek(["press", key])
            Thread.sleep(forTimeInterval: 0.4)
        }
        context.addCaption("Den Mode · → → ←", from: navigationStart, to: context.timestamp())

        print("Den Mode: fitting three columns…")
        let modeStart = context.timestamp()
        try context.peek(["press", "w"])
        Thread.sleep(forTimeInterval: 0.3)
        try context.peek(["press", "3"])
        Thread.sleep(forTimeInterval: 0.8)
        context.addCaption("Den Mode · w → 3", from: modeStart, to: context.timestamp())
        try context.peek(["press", "Escape"])

        print("Overview: returning to Research by double-click…")
        try context.click("Overview")
        try wait("the Overview") { try context.tree().contains("Close Overview") }
        Thread.sleep(forTimeInterval: 0.5)
        try context.peek(["press", "up"])
        Thread.sleep(forTimeInterval: 0.4)
        try context.peek(["press", "up"])
        Thread.sleep(forTimeInterval: 0.7)
        try context.click("Sheet URL https://den.nekonata.dev", twice: true)
        try wait("Research after Overview") {
            let state = try context.tree()
            return !state.contains("Close Overview") && state.contains("Web and terminal work")
        }
        Thread.sleep(forTimeInterval: 0.8)
    }
}
