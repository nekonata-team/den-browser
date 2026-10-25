import AppKit
import Carbon.HIToolbox
import Foundation

struct DemoError: Error, CustomStringConvertible {
    let description: String
}

func tool(_ name: String, environment: [String: String]) throws -> String {
    try run("/usr/bin/which", [name], environment: environment).trimmingCharacters(in: .whitespacesAndNewlines)
}

func observe(peekaboo: String, pid: pid_t, environment: [String: String]) throws -> [String: Any] {
    let output = try run(
        peekaboo,
        [
            "see", "--pid", String(pid), "--tree", "--no-screenshot", "--fresh", "--no-remote",
            "--json",
        ],
        environment: environment)
    let response = try parseJSONObject(output)
    guard response["success"] as? Bool == true,
        let data = response["data"] as? [String: Any]
    else { throw DemoError(description: "Invalid Peekaboo observation:\n\(output)") }
    return data
}

func tree(peekaboo: String, pid: pid_t, environment: [String: String]) throws -> String {
    guard
        let elements = try observe(peekaboo: peekaboo, pid: pid, environment: environment)["ui_elements"]
            as? [[String: Any]]
    else {
        throw DemoError(description: "Peekaboo returned no element map")
    }
    return elements.flatMap { element in
        ["identifier", "title", "label", "value"].compactMap { element[$0] as? String }
    }.joined(separator: "\n")
}

func peek(_ args: [String], peekaboo: String, target: [String], environment: [String: String]) throws {
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

func click(
    _ key: String,
    peekaboo: String,
    pid: pid_t,
    target: [String],
    environment: [String: String],
    twice: Bool = false,
    right: Bool = false
) throws {
    var candidates: [[String: Any]] = []
    try wait("the \(key) control") {
        let elements =
            try observe(peekaboo: peekaboo, pid: pid, environment: environment)["ui_elements"] as? [[String: Any]] ?? []
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
    try peek(
        ["move", "--at", position, "--global", "--smooth", "--duration", "550ms"], peekaboo: peekaboo, target: target,
        environment: environment)
    try peek(
        ["click", "--at", position, "--global"] + (twice ? ["--double"] : right ? ["--right"] : []), peekaboo: peekaboo,
        target: target, environment: environment)
}

func boardHeaders(peekaboo: String, pid: pid_t, environment: [String: String]) throws -> [String: CGRect] {
    var headers: [String: CGRect] = [:]
    for element in try observe(peekaboo: peekaboo, pid: pid, environment: environment)["ui_elements"]
        as? [[String: Any]] ?? []
    {
        if let identifier = element["identifier"] as? String, identifier.hasPrefix("board-header.") {
            headers[identifier] = try bounds(element)
        }
    }
    return headers
}

// swiftlint:disable:next function_parameter_count
func openBoard(
    _ input: String,
    using control: String,
    peekaboo: String,
    pid: pid_t,
    target: [String],
    environment: [String: String]
) throws {
    try click(control, peekaboo: peekaboo, pid: pid, target: target, environment: environment)
    try wait("Open Board") {
        try tree(peekaboo: peekaboo, pid: pid, environment: environment).contains("open-board-input")
    }
    try click("open-board-input", peekaboo: peekaboo, pid: pid, target: target, environment: environment)
    try peek(
        ["type", input, "--delay", "15", "--accept-dispatched"], peekaboo: peekaboo, target: target,
        environment: environment)
    try wait("the Open Board input") {
        try tree(peekaboo: peekaboo, pid: pid, environment: environment).contains(input)
    }
    try peek(["press", "Return"], peekaboo: peekaboo, target: target, environment: environment)
    try wait("the new Board") {
        let state = try tree(peekaboo: peekaboo, pid: pid, environment: environment)
        return !state.contains("open-board-input") && state.contains("board-header.")
    }
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

func currentInputSourceID() -> String? {
    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    return inputSourceID(current)
}

func selectInputSource(_ source: TISInputSource) throws {
    guard let identifier = inputSourceID(source) else {
        throw DemoError(description: "Could not resolve the keyboard input source identifier")
    }
    if let inputContext = NSTextInputContext.current {
        inputContext.selectedKeyboardInputSource = identifier
    }
    if currentInputSourceID() == identifier { return }
    guard TISSelectInputSource(source) == noErr else {
        throw DemoError(description: "Could not select the keyboard input source \(identifier)")
    }
    try wait("keyboard input source \(identifier)", timeout: 3) {
        currentInputSourceID() == identifier
    }
}

func terminate(_ task: Process) {
    guard task.isRunning else { return }
    task.terminate()
    try? wait("process cleanup", timeout: 5) { !task.isRunning }
    if task.isRunning { kill(task.processIdentifier, SIGKILL) }
    task.waitUntilExit()
}

func launchDemo(at bundle: URL, environment: [String: String], extraArguments: [String] = []) throws
    -> NSRunningApplication
{
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--demo", "-ApplePersistenceIgnoreState", "YES"] + extraArguments
    configuration.environment = environment
    configuration.createsNewApplicationInstance = true
    nonisolated(unsafe) var result: Result<NSRunningApplication, Error>?
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
