import Foundation

setbuf(stdout, nil)

do {
    try main()
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}

@MainActor
func main() throws {
    var scenarioName = "promotional"
    var outputPath: String?
    var overwrite = false

    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let arg = arguments.removeFirst()
        switch arg {
        case "--scenario":
            guard !arguments.isEmpty else {
                throw DemoError(description: "--scenario requires a scenario name")
            }
            scenarioName = arguments.removeFirst()
        case "--record":
            guard !arguments.isEmpty else {
                throw DemoError(description: "--record requires an output .mp4 path")
            }
            outputPath = arguments.removeFirst()
        case "--overwrite":
            overwrite = true
        default:
            throw DemoError(
                description:
                    "Usage: den-demo [--scenario promotional|agent-verify|agent-desk|agent-show-me] [--record output.mp4] [--overwrite]"
            )
        }
    }

    let scenarios: [String: any DemoScenario] = [
        PromotionalScenario.name: PromotionalScenario(),
        AgentVerifyScenario.name: AgentVerifyScenario(),
        AgentDeskScenario.name: AgentDeskScenario(),
        AgentShowMeScenario.name: AgentShowMeScenario(),
    ]

    guard let scenario = scenarios[scenarioName] else {
        throw DemoError(
            description:
                "Unknown scenario: \"\(scenarioName)\". Available: \(scenarios.keys.sorted().joined(separator: ", "))")
    }

    let output = outputPath.map { URL(fileURLWithPath: $0) }
    try runDemoHarness(scenario: scenario, output: output, overwrite: overwrite)
}
