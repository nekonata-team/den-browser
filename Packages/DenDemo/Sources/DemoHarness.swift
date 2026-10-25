import AppKit
import Carbon.HIToolbox
import Foundation

struct DemoContext {
    let app: NSRunningApplication
    let peekaboo: String
    let target: [String]
    let environment: [String: String]
    let directory: URL
    let denCLI: String
    var sceneStarted: Date
    var annotations: [[String: Any]] = []

    var pid: pid_t { app.processIdentifier }

    func timestamp() -> Int {
        Int(Date().timeIntervalSince(sceneStarted) * 1000)
    }

    @discardableResult
    func den(_ args: [String]) throws -> String {
        try DenDemo.run(denCLI, args, environment: environment)
    }

    mutating func addCaption(_ text: String, from startMs: Int, to endMs: Int) {
        annotations.append([
            "id": UUID().uuidString,
            "startMs": startMs,
            "endMs": endMs,
            "type": "text",
            "content": text,
            "textContent": text,
            "position": ["x": 32, "y": 86],
            "size": ["width": 36, "height": 8],
            "style": ["fontSize": 28, "color": "#ffffff"],
            "zIndex": 1,
        ])
    }

    func peek(_ args: [String]) throws {
        try DenDemo.peek(args, peekaboo: peekaboo, target: target, environment: environment)
    }

    func click(_ key: String, twice: Bool = false, right: Bool = false) throws {
        try DenDemo.click(
            key,
            peekaboo: peekaboo,
            pid: pid,
            target: target,
            environment: environment,
            twice: twice,
            right: right
        )
    }

    func boardHeaders() throws -> [String: CGRect] {
        try DenDemo.boardHeaders(peekaboo: peekaboo, pid: pid, environment: environment)
    }

    func openBoard(_ input: String, using control: String) throws {
        try DenDemo.openBoard(
            input,
            using: control,
            peekaboo: peekaboo,
            pid: pid,
            target: target,
            environment: environment
        )
    }

    func tree() throws -> String {
        try DenDemo.tree(peekaboo: peekaboo, pid: pid, environment: environment)
    }

    func centerCursor() throws {
        try DenDemo.centerCursor(peekaboo: peekaboo, pid: pid, target: target, environment: environment)
    }
}

@MainActor
func runDemoHarness(scenario: any DemoScenario, output: URL?, overwrite: Bool = false) throws {
    let projectOutput = output?.deletingPathExtension().appendingPathExtension("openscreen")
    if let output {
        guard output.pathExtension == "mp4" else {
            throw DemoError(description: "Output must have an .mp4 extension")
        }
        if overwrite {
            try? FileManager.default.removeItem(at: output)
            if let projectOutput {
                try? FileManager.default.removeItem(at: projectOutput)
            }
        }
        guard !FileManager.default.fileExists(atPath: output.path),
            projectOutput.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true
        else {
            throw DemoError(
                description:
                    "Choose a new .mp4 output path or pass --overwrite; existing videos and projects are not overwritten"
            )
        }
    }
    let runID = UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DenBrowserDemo/\(runID)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let suiteName = "dev.nekonata.denbrowser.demo.\(runID)"
    defer { UserDefaults().removePersistentDomain(forName: suiteName) }
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "DEN_PROFILE")
    environment.removeValue(forKey: "DEN_BOARD_ID")
    let socket = "/tmp/den-demo-\(runID).sock"
    environment["DEN_SOCKET"] = socket
    defer { try? FileManager.default.removeItem(atPath: socket) }
    environment["DEN_DEMO_RUN_ID"] = runID

    let peekaboo = try tool("peekaboo", environment: environment)
    let openscreen = try output.map { _ in try tool("openscreen", environment: environment) }
    let permissions = try parseJSONObject(
        run(peekaboo, ["permissions", "status", "--no-remote", "--json"], environment: environment))
    let permissionData = permissions["data"] as? [String: Any]
    let missing = (permissionData?["permissions"] as? [[String: Any]] ?? []).filter {
        ($0["isRequired"] as? Bool == true) && ($0["isGranted"] as? Bool != true)
    }
    guard permissions["success"] as? Bool == true, permissionData?["permissions"] != nil, missing.isEmpty else {
        throw DemoError(
            description:
                "Grant Peekaboo Screen Recording and Accessibility permissions in System Settings before running the demo"
        )
    }
    guard let previousInputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
        let sources = TISCreateInputSourceList(
            [kTISPropertyInputSourceID: "com.apple.keylayout.ABC"] as CFDictionary, false
        )?.takeRetainedValue() as? [TISInputSource],
        let abcInputSource = sources.first
    else { throw DemoError(description: "The ABC keyboard input source must be available before running the demo") }
    defer {
        do {
            try selectInputSource(previousInputSource)
        } catch {
            fputs("Error restoring the keyboard input source: \(error)\n", stderr)
        }
    }
    var extraArguments: [String] = []
    if let initialProfileURL = try scenario.initialProfileURL(directory: directory) {
        extraArguments += ["--initial-profile", initialProfileURL.path]
    }
    let bundle = URL(fileURLWithPath: ".derived-data/Build/Products/Debug/Den Browser.app")
    let app = try launchDemo(at: bundle, environment: environment, extraArguments: extraArguments)
    defer {
        app.terminate()
        try? wait("demo cleanup", timeout: 5) { app.isTerminated }
        if !app.isTerminated { app.forceTerminate() }
    }

    // MARK: - Window observation and activation

    print("Starting isolated demo (\(type(of: scenario).name))…")
    let target = ["--pid", String(app.processIdentifier), "--foreground", "--no-remote"]
    try wait("the Demo profile menu") {
        let menu = try? run(
            peekaboo, ["menu", "list", "--pid", String(app.processIdentifier), "--no-remote", "--json"],
            environment: environment)
        return menu?.contains("Demo") == true
    }
    _ = try run(
        peekaboo,
        ["menu", "click", "--path", "Profile > Demo", "--pid", String(app.processIdentifier), "--no-remote"],
        environment: environment)
    var lastObservation = "No window observation yet"
    do {
        try wait("the demo window") {
            guard !app.isTerminated else { throw DemoError(description: "Demo app exited before opening its window") }
            guard app.activate() else { return false }
            do {
                lastObservation = try tree(peekaboo: peekaboo, pid: app.processIdentifier, environment: environment)
                return lastObservation.contains("Profile: Demo")
            } catch {
                lastObservation = String(describing: error)
                return false
            }
        }
    } catch {
        throw DemoError(description: "\(error)\nLast observation:\n\(lastObservation)")
    }
    try selectInputSource(abcInputSource)
    print("Keyboard input source: ABC")

    // MARK: - Scenario Preparation (Pre-recording)

    let denCLI = bundle.appendingPathComponent("Contents/MacOS/den").path
    var context = DemoContext(
        app: app,
        peekaboo: peekaboo,
        target: target,
        environment: environment,
        directory: directory,
        denCLI: denCLI,
        sceneStarted: Date()
    )
    try scenario.prepare(context: &context)
    try? context.centerCursor()

    // MARK: - Recording

    let recorderInput = Pipe()
    var recorder: Process?
    defer {
        if let recorder, recorder.isRunning {
            try? recorderInput.fileHandleForWriting.write(contentsOf: Data("stop\n".utf8))
            try? wait("recording cleanup", timeout: 10) { !recorder.isRunning }
            terminate(recorder)
        }
    }
    let project = directory.appendingPathComponent("demo.openscreen")
    if let openscreen {
        let log = directory.appendingPathComponent("record.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let task = process(
            openscreen, ["record", "--window", "Demo", "--project", project.path, "--json"], environment: environment)
        task.standardInput = recorderInput
        task.standardOutput = handle
        task.standardError = handle
        try task.run()
        recorder = task
        try wait("recording to start", timeout: 30) {
            let text = try String(contentsOf: log, encoding: .utf8)
            guard task.isRunning else { throw DemoError(description: "Recorder exited:\n\(text)") }
            return text.contains("Recording started")
        }
    }

    // MARK: - Scenario Execution

    context.sceneStarted = Date()
    try scenario.run(context: &context)

    // MARK: - Export

    if let recorder, let openscreen, let output, let projectOutput {
        try recorderInput.fileHandleForWriting.write(contentsOf: Data("stop\n".utf8))
        try wait("recording to finish", timeout: 60) { !recorder.isRunning }
        guard recorder.terminationStatus == 0 else { throw DemoError(description: "Recording failed") }
        var document = try parseJSONObject(String(contentsOf: project, encoding: .utf8))
        guard var editor = document["editor"] as? [String: Any] else {
            throw DemoError(description: "Unsupported OpenScreen project format")
        }
        editor["zoomRegions"] = [[String: Any]]()
        editor["annotationRegions"] = context.annotations
        editor["aspectRatio"] = "16:9"
        editor["padding"] = 35
        editor["cursorSize"] = 2.2
        editor["cursorSmoothing"] = 0.85
        editor["cursorMotionBlur"] = 0.4
        editor["cursorClickBounce"] = 1.15
        editor["motionBlurAmount"] = 0.25
        document["editor"] = editor
        try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            .write(to: projectOutput, options: .atomic)
        print("Exporting demo video…")
        print(
            try run(
                openscreen, ["export", projectOutput.path, "-o", output.path, "--auto-zoom"], environment: environment))
        guard (try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
            throw DemoError(description: "Export produced an empty video")
        }
        print("Saved: \(output.path)")
        print("Editable project: \(projectOutput.path)")
    }
    print("Demo completed.")
}
