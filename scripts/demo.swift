#!/usr/bin/env swift
import AppKit
import Carbon.HIToolbox
import Foundation

setbuf(stdout, nil)

do {
    try demo()
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}

func demo() throws {
    // MARK: - Preparation

    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.isEmpty || (arguments.count == 2 && arguments[0] == "--record") else {
        throw DemoError(description: "Usage: swift scripts/demo.swift [--record output.mp4]")
    }
    let output = arguments.last.map { URL(fileURLWithPath: $0) }
    let projectOutput = output?.deletingPathExtension().appendingPathExtension("openscreen")
    if let output {
        guard output.pathExtension == "mp4",
            !FileManager.default.fileExists(atPath: output.path),
            projectOutput.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true
        else {
            throw DemoError(
                description: "Choose a new .mp4 output path; existing videos and projects are not overwritten")
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
    let peekaboo = try tool("peekaboo")
    let openscreen = try output.map { _ in try tool("openscreen") }
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
    let bundle = URL(fileURLWithPath: ".derived-data/Build/Products/Debug/Den Browser.app")
    let app = try launchDemo(at: bundle, environment: environment)
    defer {
        app.terminate()
        try? wait("demo cleanup", timeout: 5) { app.isTerminated }
        if !app.isTerminated { app.forceTerminate() }
    }

    // MARK: - Window observation and activation

    print("Starting isolated demo…")
    let target = ["--pid", String(app.processIdentifier), "--foreground", "--no-remote"]
    try wait("the Demo profile menu") {
        let menu = try? run(
            peekaboo, ["menu", "list", "--pid", String(app.processIdentifier), "--no-remote", "--json"],
            environment: environment)
        return menu?.contains("Demo") == true
    }
    // A data-backed WindowGroup can launch with no window; open this Profile explicitly.
    _ = try run(
        peekaboo,
        ["menu", "click", "--path", "Profile > Demo", "--pid", String(app.processIdentifier), "--no-remote"],
        environment: environment)
    var lastObservation = "No window observation yet"
    do {
        try wait("the demo window") {
            guard !app.isTerminated else { throw DemoError(description: "Demo app exited before opening its window") }
            guard app.activate() else {
                return false
            }
            do {
                lastObservation = try tree()
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

    // MARK: - Demo scenario

    let sceneStarted = Date()
    var annotations: [[String: Any]] = []
    print("Research: collecting product and source pages…")
    try openBoard("https://den.nekonata.dev", using: "Open Board")
    try wait("the product page", timeout: 30) { try tree().contains("Web and terminal work") }
    Thread.sleep(forTimeInterval: 0.5)
    try openBoard("https://github.com/nekonata-team/den-browser", using: "Open Board at End of Desk")
    try wait("the repository page", timeout: 30) { try tree().contains("GitHub") }
    Thread.sleep(forTimeInterval: 0.5)

    print("Build: creating a separate Desk…")
    try click("New Desk")
    try wait("the Desk preset picker") { try tree().contains("Empty") }
    try peek(["type", "Build", "--delay", "40", "--accept-dispatched"])
    try click("Create \"Build\"")
    try wait("the Build Desk") { try tree().contains("2. Build") }

    print("Opening Terminal Board…")
    try openBoard(":terminal", using: "Open Board")
    Thread.sleep(forTimeInterval: 0.3)
    try peek(["type", "echo hello", "--delay", "25", "--accept-dispatched"])
    try peek(["press", "Return"])
    Thread.sleep(forTimeInterval: 0.5)

    print("Build: duplicating Terminal from the Header menu…")
    let originalHeaders = try boardHeaders()
    guard originalHeaders.count == 1, let originalHeader = originalHeaders.keys.first else {
        throw DemoError(description: "Expected one Terminal Board before duplication")
    }
    try click(originalHeader, right: true)
    try wait("the Terminal Header menu") { try tree().contains("Duplicate Terminal Board") }
    Thread.sleep(forTimeInterval: 0.4)
    try click("Duplicate Terminal Board")
    try wait("the duplicated Terminal Board") {
        let headers = try boardHeaders()
        let added = Set(headers.keys).subtracting(originalHeaders.keys)
        return headers.count == 2 && added.count == 1
    }
    Thread.sleep(forTimeInterval: 0.3)

    print("Gemini: opening a three-Board preset…")
    try click("New Desk")
    try wait("the Desk preset picker") { try tree().contains("Empty") }
    try click("Gemini")
    try click("Create")
    try wait("the Gemini Desk") { try tree().contains("3. Gemini") }
    Thread.sleep(forTimeInterval: 0.8)

    print("Gemini: navigating right, right, left in Den Mode…")
    try peek(["press", "ctrl+comma"])
    try wait("Den Mode") { try tree().contains("DEN MODE") }
    Thread.sleep(forTimeInterval: 0.3)
    let navigationStart = timestamp()
    for key in ["right", "right", "left"] {
        try peek(["press", key])
        Thread.sleep(forTimeInterval: 0.4)
    }
    addCaption("Den Mode · → → ←", from: navigationStart, to: timestamp())

    print("Den Mode: fitting three columns…")
    let modeStart = timestamp()
    try peek(["press", "w"])
    Thread.sleep(forTimeInterval: 0.3)
    try peek(["press", "3"])
    Thread.sleep(forTimeInterval: 0.8)
    addCaption("Den Mode · w → 3", from: modeStart, to: timestamp())
    try peek(["press", "Escape"])

    print("Overview: returning to Research by double-click…")
    try click("Overview")
    try wait("the Overview") { try tree().contains("Close Overview") }
    Thread.sleep(forTimeInterval: 0.5)
    try peek(["press", "up"])
    Thread.sleep(forTimeInterval: 0.4)
    try peek(["press", "up"])
    Thread.sleep(forTimeInterval: 0.7)
    try click("Sheet URL https://den.nekonata.dev", twice: true)
    try wait("Research after Overview") {
        let state = try tree()
        return !state.contains("Close Overview") && state.contains("Web and terminal work")
    }
    Thread.sleep(forTimeInterval: 0.8)
    _ = try run(
        peekaboo,
        [
            "see", "--pid", String(app.processIdentifier), "--no-elements", "--json", "--no-remote",
            "--path", directory.appendingPathComponent("final.png").path,
        ], environment: environment)

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
        editor["annotationRegions"] = annotations
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
        print("Exporting video…")
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

    // MARK: - Scenario helpers

    func tool(_ name: String) throws -> String {
        try run("/usr/bin/which", [name], environment: environment).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func observe() throws -> [String: Any] {
        let output = try run(
            peekaboo,
            [
                "see", "--pid", String(app.processIdentifier), "--tree", "--no-screenshot", "--fresh", "--no-remote",
                "--json",
            ],
            environment: environment)
        let response = try parseJSONObject(output)
        guard response["success"] as? Bool == true,
            let data = response["data"] as? [String: Any]
        else { throw DemoError(description: "Invalid Peekaboo observation:\n\(output)") }
        return data
    }
    func tree() throws -> String {
        guard let elements = try observe()["ui_elements"] as? [[String: Any]] else {
            throw DemoError(description: "Peekaboo returned no element map")
        }
        return elements.flatMap { element in
            ["identifier", "title", "label", "value"].compactMap { element[$0] as? String }
        }.joined(separator: "\n")
    }
    func peek(_ args: [String]) throws {
        _ = try run(peekaboo, args + target, environment: environment)
    }
    func bounds(_ element: [String: Any]) throws -> CGRect {
        guard let frame = element["bounds"] as? [String: Double],
            let originX = frame["x"], let originY = frame["y"], let width = frame["width"],
            let height = frame["height"],
            width > 0, height > 0
        else { throw DemoError(description: "Element has no usable bounds") }
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
    func click(_ key: String, twice: Bool = false, right: Bool = false) throws {
        var candidates: [[String: Any]] = []
        try wait("the \(key) control") {
            let elements = try observe()["ui_elements"] as? [[String: Any]] ?? []
            candidates = elements.filter { element in
                (element["is_actionable"] as? Bool == true || twice || key.hasPrefix("board-header."))
                    && ["identifier", "label", "title"].contains { field in
                        guard let value = element[field] as? String else { return false }
                        return twice ? value.contains(key) : value.hasPrefix(key)
                    }
            }
            return candidates.count == 1
        }
        let frame = try bounds(candidates[0])
        let position = "\(Int(frame.midX)),\(Int(frame.midY))"
        try peek(["move", "--at", position, "--global", "--smooth", "--duration", "550ms"])
        try peek(["click", "--at", position, "--global"] + (twice ? ["--double"] : right ? ["--right"] : []))
    }
    func boardHeaders() throws -> [String: CGRect] {
        var headers: [String: CGRect] = [:]
        for element in try observe()["ui_elements"] as? [[String: Any]] ?? [] {
            if let identifier = element["identifier"] as? String, identifier.hasPrefix("board-header.") {
                headers[identifier] = try bounds(element)
            }
        }
        return headers
    }
    func openBoard(_ input: String, using control: String) throws {
        try click(control)
        try wait("Open Board") { try tree().contains("open-board-input") }
        try click("open-board-input")
        try peek(["type", input, "--delay", "15", "--accept-dispatched"])
        try wait("the Open Board input") { try tree().contains(input) }
        try peek(["press", "Return"])
        try wait("the new Board") {
            let state = try tree()
            return !state.contains("open-board-input") && state.contains("board-header.")
        }
    }
    func timestamp() -> Int { Int(Date().timeIntervalSince(sceneStarted) * 1000) }
    func addCaption(_ text: String, from startMs: Int, to endMs: Int) {
        annotations.append([
            "id": UUID().uuidString, "startMs": startMs, "endMs": endMs,
            "type": "text", "content": text, "textContent": text,
            "position": ["x": 32, "y": 86], "size": ["width": 36, "height": 8],
            "style": ["fontSize": 28, "color": "#ffffff"], "zIndex": 1,
        ])
    }
}

// MARK: - Process and system helpers

struct DemoError: Error, CustomStringConvertible {
    let description: String
}

func process(_ executable: String, _ arguments: [String], environment: [String: String]) -> Process {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    task.environment = environment
    return task
}

func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> String {
    let task = process(executable, arguments, environment: environment)
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    try task.run()
    // Drain before waiting so a full pipe cannot deadlock the child.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard let output = String(data: data, encoding: .utf8) else {
        throw DemoError(description: "\(executable) returned invalid UTF-8 output")
    }
    guard task.terminationStatus == 0 else {
        throw DemoError(description: "\(executable) \(arguments.joined(separator: " ")) failed:\n\(output)")
    }
    return output
}

func wait(_ description: String, timeout: TimeInterval = 20, until ready: () throws -> Bool) throws {
    let deadline = Date().addingTimeInterval(timeout)
    var lastError: Error?
    repeat {
        do {
            if try ready() { return }
        } catch {
            lastError = error
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    let detail = lastError.map { "\nLast observation error: \($0)" } ?? ""
    throw DemoError(description: "Timed out waiting for \(description)\(detail)")
}

func parseJSONObject(_ text: String) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
        throw DemoError(description: "Expected a JSON object: \(text)")
    }
    return value
}

func inputSourceID(_ source: TISInputSource) -> String? {
    guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}

func selectInputSource(_ source: TISInputSource) throws {
    guard let identifier = inputSourceID(source), TISSelectInputSource(source) == noErr else {
        throw DemoError(description: "Could not select the keyboard input source")
    }
    try wait("keyboard input source \(identifier)", timeout: 3) {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        return inputSourceID(current) == identifier
    }
}

func terminate(_ task: Process) {
    guard task.isRunning else { return }
    task.terminate()
    try? wait("process cleanup", timeout: 5) { !task.isRunning }
    if task.isRunning { kill(task.processIdentifier, SIGKILL) }
    task.waitUntilExit()
}

func launchDemo(at bundle: URL, environment: [String: String]) throws -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--demo", "-ApplePersistenceIgnoreState", "YES"]
    configuration.environment = environment
    configuration.createsNewApplicationInstance = true
    var result: Result<NSRunningApplication, Error>?
    NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { app, error in
        if let app {
            result = .success(app)
        } else {
            result = .failure(error ?? DemoError(description: "macOS did not return the launched demo app"))
        }
    }
    let deadline = Date().addingTimeInterval(20)
    while result == nil && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard let result else { throw DemoError(description: "Timed out launching the demo app") }
    return try result.get()
}
