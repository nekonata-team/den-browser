import ArgumentParser
import DenIPCProtocol
import Foundation

struct SheetNavigateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "navigate",
        abstract: "Navigate Current Sheet in the target Web Board to a URL or search query")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "URL or search query to open") var url: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .open(DenSheetOpenPayload(url: url)),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetURLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "url",
        abstract: "Print Current Sheet URL of the target Web Board")

    @OptionGroup var target: SheetTargetOptions

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .url,
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetReloadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Reload Current Sheet in the target Web Board")

    @OptionGroup var target: SheetTargetOptions

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .reload,
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetEvalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eval",
        abstract: "Evaluate JavaScript in the target Web Board")

    @OptionGroup var target: SheetTargetOptions
    @Argument(parsing: .remaining, help: "JavaScript code to evaluate") var scriptParts: [String]

    func run() throws {
        let script = scriptParts.joined(separator: " ")
        guard !script.isEmpty else {
            throw ValidationError("Please provide JavaScript code to evaluate")
        }
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .eval(DenSheetEvalPayload(script: script)),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Print visible text from the target Web Board")

    @OptionGroup var target: SheetTargetOptions

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .text,
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetSnapshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Extract semantic DOM tree with short references (@e1, @e2)")

    @OptionGroup var target: SheetTargetOptions
    @Flag(name: [.customShort("i"), .long], help: "Filter to interactive elements only (default)")
    var interactive: Bool = false
    @Flag(name: .long, help: "Include the full semantic tree")
    var full: Bool = false
    @Option(name: .long, help: "Limit the snapshot to one CSS selector or element reference")
    var within: String?

    func run() throws {
        guard !(interactive && full) else {
            throw ValidationError("Please choose either --interactive or --full")
        }
        try DenIPCClient.execute(
            operation: .sheet(
                command: .snapshot(DenSheetSnapshotPayload(full: full, within: within)),
                target: try DenIPCClient.boardTarget(target.target.boardID)
            ),
            options: target.target.common
        )
    }
}

struct SheetQueryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Inspect matching DOM elements")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "CSS selector to query")
    var selector: String
    @Flag(name: .long, help: "Keep only visible elements")
    var visible: Bool = false
    @Flag(name: .long, help: "Return all matching elements")
    var all: Bool = false
    @Option(name: .long, help: "Comma-separated fields to return")
    var fields: String?

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .query(
                    DenSheetQueryPayload(
                        selector: selector,
                        visible: visible,
                        all: all,
                        fields: fields
                    )
                ),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetClickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click an element by reference (@e1) or CSS selector")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector to click")
    var targetElement: String?
    @Option(name: .long, help: "ARIA or implicit role to match")
    var role: String?
    @Option(name: .long, help: "Accessible name to match")
    var name: String?
    @Flag(name: .long, help: "Require an exact accessible-name match")
    var exact: Bool = false
    @Flag(name: .long, help: "Open the clicked link in a new Web Board")
    var newBoard: Bool = false
    @Flag(name: .long, help: "Focus the newly created Web Board (with --new-board)")
    var focus: Bool = false

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .click(
                    DenSheetClickPayload(
                        target: targetElement,
                        role: role,
                        name: name,
                        exact: exact,
                        newBoard: newBoard,
                        focus: focus
                    )
                ),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetDblclickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dblclick",
        abstract: "Double-click an element by reference (@e1) or CSS selector"
    )

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector to double-click")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .dblclick(DenSheetElementTargetPayload(target: targetElement)),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetFocusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Focus an element by reference (@e1) or CSS selector"
    )

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector to focus")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .focus(DenSheetElementTargetPayload(target: targetElement)),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetFillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fill",
        abstract: "Fill an input, textarea, or editable element with text by reference or selector")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector to fill")
    var targetElement: String
    @Argument(parsing: .remaining, help: "Text value to fill into the input")
    var valueParts: [String]

    func run() throws {
        guard !valueParts.isEmpty else {
            throw ValidationError("Please provide a text value to fill")
        }
        let value = valueParts.joined(separator: " ")
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .fill(DenSheetFillPayload(target: targetElement, value: value)),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetTypeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into an element by reference/selector or into the currently focused element"
    )

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Target element reference/selector, or text if typing into focused element")
    var firstArg: String
    @Argument(parsing: .remaining, help: "Text to type if target element was specified")
    var remainingParts: [String] = []

    func run() throws {
        let payload: DenSheetTypePayload
        if remainingParts.isEmpty {
            payload = DenSheetTypePayload(target: nil, text: firstArg)
        } else {
            payload = DenSheetTypePayload(target: firstArg, text: remainingParts.joined(separator: " "))
        }
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .type(payload),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetDragCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drag",
        abstract: "Drag an element by reference (@e1) or selector to another element or relative offset"
    )

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Source element reference (@e1) or CSS selector to drag")
    var source: String
    @Argument(help: "Target element reference (@e1) or CSS selector to drop onto (optional)")
    var destination: String?
    @Option(name: .customLong("dx"), help: "Horizontal delta to drag in pixels (positive = right, negative = left)")
    var deltaX: Double?
    @Option(name: .customLong("dy"), help: "Vertical delta to drag in pixels (positive = down, negative = up)")
    var deltaY: Double?
    @Option(name: .long, help: "Number of intermediate move events (default: 5)")
    var steps: Int = 5

    func validate() throws {
        guard destination != nil || deltaX != nil || deltaY != nil else {
            throw ValidationError("Provide a target element or at least one of --dx / --dy")
        }
    }

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .drag(
                    DenSheetDragPayload(
                        source: source,
                        destination: destination,
                        deltaX: deltaX,
                        deltaY: deltaY,
                        steps: steps
                    )
                ),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetMouseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mouse",
        abstract: "Dispatch mouse events (move, down, up, click, wheel)",
        subcommands: [
            SheetMouseMoveCommand.self,
            SheetMouseDownCommand.self,
            SheetMouseUpCommand.self,
            SheetMouseClickCommand.self,
            SheetMouseWheelCommand.self,
        ]
    )
}

struct SheetMouseMoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move mouse pointer to viewport coordinates"
    )

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "X coordinate in viewport pixels") var coordX: Double
    @Argument(help: "Y coordinate in viewport pixels") var coordY: Double

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .mouse(.move(DenSheetMousePayload(coordX: coordX, coordY: coordY))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetMouseDownCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "down",
        abstract: "Press mouse button down"
    )

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Button to press (left, right, middle; default: left)")
    var button: String?

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .mouse(.down(DenSheetMousePayload(button: button))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetMouseUpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up",
        abstract: "Release mouse button"
    )

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Button to release (left, right, middle; default: left)")
    var button: String?

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .mouse(.release(DenSheetMousePayload(button: button))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetMouseClickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click at viewport coordinates"
    )

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "X coordinate in viewport pixels") var coordX: Double
    @Argument(help: "Y coordinate in viewport pixels") var coordY: Double
    @Option(name: .long, help: "Mouse button (left, right, middle; default: left)")
    var button: String?
    @Option(name: .long, help: "Click count (1 for click, 2 for double-click; default: 1)")
    var count: Int?

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .mouse(
                    .click(
                        DenSheetMousePayload(
                            coordX: coordX,
                            coordY: coordY,
                            button: button,
                            count: count
                        ))
                ),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetMouseWheelCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wheel",
        abstract: "Scroll mouse wheel"
    )

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Vertical scroll delta in pixels") var deltaY: Double
    @Option(name: .customLong("dx"), help: "Horizontal scroll delta in pixels (default: 0)")
    var deltaX: Double?

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .mouse(.wheel(DenSheetMousePayload(deltaX: deltaX, deltaY: deltaY))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetInteractCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interact",
        abstract: "Run multiple Sheet actions from a script, file, or stdin",
        discussion: """
            Executes a series of Sheet actions line-by-line. Add --snapshot to include the final semantic snapshot.
            Each line or semicolon-separated statement uses the same syntax as 'den board web <subcommand>'.

            Available actions:
              click <ref|selector>              Click an element (e.g. click @e1)
              dblclick <ref|selector>           Double-click an element
              focus <ref|selector>              Focus an element
              fill <ref|selector> <text>        Fill an input, textarea, or editable element with text
              type [<ref|selector>] <text>      Type text into an element or the focused element
              drag <src> [<tgt>] [--dx] [--dy]  Drag an element to a target or relative offset
              mouse <action> ...                Dispatch mouse events (move, click, down, up, wheel)
              press <key>                       Press a key (Enter, Escape, Tab, ArrowDown, etc.)
              scroll [direction|ref|selector]   Scroll the page or scroll an element into view
              wait <ref|--load|--url|--text>    Wait for DOM state, load state, or URL
              screenshot [output-path]          Capture a PNG screenshot
              navigate <url>                   Navigate to a URL
              reload                            Reload current Sheet
              back / forward                    Navigate history
              eval <javascript>                 Evaluate JavaScript code

            Examples:
              den board web interact "click @e1; fill @e2 Hello; press Enter"
              den board web interact << 'EOF'
              click @e1
              fill @e2 "query text"
              press Enter
              wait --load networkidle
              screenshot /tmp/result.png
              EOF
              den board web interact path/to/script.den
            """)

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Script text, script file path, or - for stdin (defaults to stdin if piped)")
    var scriptOrPath: String?
    @Flag(name: .long, help: "Include the full semantic tree (requires --snapshot)")
    var full: Bool = false

    func run() throws {
        guard !full || target.snapshot else {
            throw ValidationError("--full requires --snapshot")
        }
        let script = try readScript()
        let steps = try DenSheetScriptParser.parse(script)
        guard !steps.isEmpty else {
            throw ValidationError("Script contains no valid actions")
        }
        let payload = DenSheetInteractPayload(steps: steps)
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .interact(payload),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshot ? DenSheetSnapshotPayload(full: full) : nil
            ),
            options: target.target.common
        )
    }

    private func readScript() throws -> String {
        guard let scriptOrPath else {
            guard isatty(fileno(stdin)) == 0 else {
                throw ValidationError("Please provide a script, a script file path, or pipe script into stdin")
            }
            return try readStandardInput()
        }

        if scriptOrPath == "-" {
            return try readStandardInput()
        }
        if FileManager.default.fileExists(atPath: scriptOrPath) {
            guard let content = try? String(contentsOfFile: scriptOrPath, encoding: .utf8) else {
                throw ValidationError("Could not read file at \(scriptOrPath)")
            }
            return content
        }
        return scriptOrPath
    }

    private func readStandardInput() throws -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard
            let text = String(data: data, encoding: .utf8),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ValidationError("Standard input was empty")
        }
        return text
    }
}

private enum DenSheetScriptParser {
    static func parse(_ script: String) throws -> [DenSheetInteractStep] {
        var steps: [DenSheetInteractStep] = []
        let lines = script.components(separatedBy: .newlines)

        for (zeroBasedIndex, rawLine) in lines.enumerated() {
            let lineNumber = zeroBasedIndex + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let commandStrings = try splitCommands(trimmed, line: lineNumber)
            for commandString in commandStrings {
                let tokens = try splitTokens(commandString, line: lineNumber)
                guard let commandName = tokens.first else { continue }
                let command = try command(
                    for: commandName,
                    arguments: Array(tokens.dropFirst()),
                    line: lineNumber
                )
                steps.append(
                    DenSheetInteractStep(
                        line: lineNumber,
                        text: commandString,
                        command: command
                    )
                )
            }
        }
        return steps
    }

    private static func command(
        for commandName: String,
        arguments: [String],
        line: Int
    ) throws -> DenIPCCommand.Sheet {
        func usage(_ message: String) -> ValidationError {
            ValidationError("Line \(line): \(message)")
        }

        func requireArguments(_ count: ClosedRange<Int>, _ message: String) throws {
            guard count.contains(arguments.count) else { throw usage(message) }
        }

        func parseOptions(
            _ input: [String],
            valued: Set<String>,
            flags: Set<String>
        ) throws -> (positionals: [String], values: [String: String], flags: Set<String>) {
            var positionals: [String] = []
            var values: [String: String] = [:]
            var foundFlags: Set<String> = []
            var index = 0
            var endOfOptions = false
            while index < input.count {
                let argument = input[index]
                if endOfOptions || !argument.hasPrefix("-") {
                    positionals.append(argument)
                    index += 1
                    continue
                }
                if argument == "--" {
                    endOfOptions = true
                    index += 1
                    continue
                }
                let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
                let name = parts[0]
                if valued.contains(name) {
                    if parts.count == 2 {
                        values[name] = parts[1]
                    } else {
                        index += 1
                        guard index < input.count else { throw usage("Missing value for \(name)") }
                        values[name] = input[index]
                    }
                } else if flags.contains(name) {
                    foundFlags.insert(name)
                } else {
                    throw usage("Unknown option \(name)")
                }
                index += 1
            }
            return (positionals, values, foundFlags)
        }

        func doubleValue(_ option: String, from values: [String: String]) throws -> Double? {
            guard let rawValue = values[option] else { return nil }
            guard let value = Double(rawValue), value.isFinite else {
                throw usage("Invalid value for \(option): \(rawValue)")
            }
            return value
        }

        switch commandName {
        case "url":
            try requireArguments(0...0, "url does not accept arguments")
            return .url

        case "reload":
            try requireArguments(0...0, "reload does not accept arguments")
            return .reload

        case "text":
            try requireArguments(0...0, "text does not accept arguments")
            return .text

        case "back":
            try requireArguments(0...0, "back does not accept arguments")
            return .back

        case "forward":
            try requireArguments(0...0, "forward does not accept arguments")
            return .forward

        case "navigate":
            try requireArguments(1...1, "Usage: den board web navigate <url>")
            return .open(DenSheetOpenPayload(url: arguments[0]))

        case "eval":
            guard !arguments.isEmpty else { throw usage("Usage: den board web eval <javascript>") }
            return .eval(DenSheetEvalPayload(script: arguments.joined(separator: " ")))

        case "press":
            try requireArguments(1...1, "Usage: den board web press <key>")
            return .press(DenSheetPressPayload(key: arguments[0]))

        case "scroll":
            try requireArguments(0...1, "Usage: den board web scroll [<direction|amount|target>]")
            return .scroll(DenSheetScrollPayload(directionOrTarget: arguments.first))

        case "wait":
            let parsed = try parseOptions(
                arguments,
                valued: ["--state", "--url", "--text", "--load", "--fn", "--timeout"],
                flags: []
            )
            let modes = [
                parsed.positionals.first,
                parsed.values["--url"],
                parsed.values["--text"],
                parsed.values["--load"],
                parsed.values["--fn"],
            ].compactMap { $0 }.count
            guard modes == 1 else {
                throw usage("Provide exactly one of a selector/ref, --url, --text, --load, or --fn")
            }
            guard parsed.positionals.count <= 1 else {
                throw usage("Usage: den board web wait <selector|ref> [options]")
            }
            if parsed.positionals.isEmpty, parsed.values["--state"] != nil {
                throw usage("--state requires a selector or element reference")
            }
            if let target = parsed.positionals.first, Double(target) != nil {
                throw usage("Duration waits are no longer supported; use --state, --url, --text, --load, or --fn")
            }
            let state = parsed.values["--state"]
            if let state, !["attached", "visible", "hidden", "detached"].contains(state.lowercased()) {
                throw usage("Invalid state: \(state)")
            }
            let loadState = parsed.values["--load"]
            if let loadState, !["domcontentloaded", "load", "networkidle"].contains(loadState.lowercased()) {
                throw usage("Invalid load state: \(loadState)")
            }
            if let text = parsed.values["--text"], text.isEmpty { throw usage("Text must not be empty") }
            if let function = parsed.values["--fn"], function.isEmpty {
                throw usage("JavaScript condition must not be empty")
            }
            let timeout = try doubleValue("--timeout", from: parsed.values) ?? 10
            return .wait(
                DenSheetWaitPayload(
                    target: parsed.positionals.first,
                    state: state,
                    url: parsed.values["--url"],
                    text: parsed.values["--text"],
                    loadState: loadState,
                    function: parsed.values["--fn"],
                    timeout: timeout
                )
            )

        case "screenshot":
            try requireArguments(0...1, "Usage: den board web screenshot [<output-path>]")
            return .screenshot(DenSheetScreenshotPayload(outputPath: arguments.first))

        case "snapshot":
            let parsed = try parseOptions(arguments, valued: ["--within"], flags: ["--full", "--interactive", "-i"])
            guard parsed.positionals.isEmpty else {
                throw usage("Usage: den board web snapshot [--interactive|--full] [--within <selector|ref>]")
            }
            let interactive = parsed.flags.contains("--interactive") || parsed.flags.contains("-i")
            guard !(parsed.flags.contains("--full") && interactive) else {
                throw usage("Please choose either --interactive or --full")
            }
            return .snapshot(
                DenSheetSnapshotPayload(
                    full: parsed.flags.contains("--full"),
                    within: parsed.values["--within"]
                )
            )

        case "query":
            let parsed = try parseOptions(arguments, valued: ["--fields"], flags: ["--visible", "--all"])
            guard parsed.positionals.count == 1, !parsed.positionals[0].isEmpty else {
                throw usage("Usage: den board web query <selector>")
            }
            return .query(
                DenSheetQueryPayload(
                    selector: parsed.positionals[0],
                    visible: parsed.flags.contains("--visible"),
                    all: parsed.flags.contains("--all"),
                    fields: parsed.values["--fields"]
                )
            )

        case "click":
            let parsed = try parseOptions(
                arguments,
                valued: ["--role", "--name"],
                flags: ["--exact", "--new-board", "--focus"]
            )
            guard parsed.positionals.count <= 1 else {
                throw usage("Usage: den board web click <@ref|selector> or --role <role> --name <name>")
            }
            let target = parsed.positionals.first
            let role = parsed.values["--role"]
            let name = parsed.values["--name"]
            guard target != nil || (role != nil && name != nil) else {
                throw usage("Usage: den board web click <@ref|selector> or --role <role> --name <name>")
            }
            guard target == nil || (role == nil && name == nil) else {
                throw usage("Provide either a selector/ref or --role and --name, not both")
            }
            return .click(
                DenSheetClickPayload(
                    target: target,
                    role: role,
                    name: name,
                    exact: parsed.flags.contains("--exact"),
                    newBoard: parsed.flags.contains("--new-board"),
                    focus: parsed.flags.contains("--focus")
                )
            )

        case "dblclick", "focus":
            try requireArguments(1...1, "Usage: den board web \(commandName) <@ref|selector>")
            let payload = DenSheetElementTargetPayload(target: arguments[0])
            if commandName == "dblclick" {
                return .dblclick(payload)
            }
            return .focus(payload)

        case "fill":
            guard arguments.count >= 2 else { throw usage("Usage: den board web fill <@ref|selector> <value>") }
            return .fill(
                DenSheetFillPayload(target: arguments[0], value: arguments.dropFirst().joined(separator: " "))
            )

        case "type":
            guard !arguments.isEmpty else { throw usage("Usage: den board web type [<@ref|selector>] <text>") }
            let payload =
                arguments.count == 1
                ? DenSheetTypePayload(target: nil, text: arguments[0])
                : DenSheetTypePayload(target: arguments[0], text: arguments.dropFirst().joined(separator: " "))
            return .type(payload)

        case "drag":
            let parsed = try parseOptions(arguments, valued: ["--dx", "--dy", "--steps"], flags: [])
            guard parsed.positionals.count >= 1, parsed.positionals.count <= 2 else {
                throw usage("Usage: den board web drag <source> [<target>] [--dx <dx>] [--dy <dy>] [--steps <steps>]")
            }
            let deltaX = try doubleValue("--dx", from: parsed.values)
            let deltaY = try doubleValue("--dy", from: parsed.values)
            let steps: Int
            if let rawSteps = parsed.values["--steps"] {
                guard let parsedSteps = Int(rawSteps) else { throw usage("Invalid value for --steps: \(rawSteps)") }
                steps = parsedSteps
            } else {
                steps = 5
            }
            guard parsed.positionals.count == 2 || deltaX != nil || deltaY != nil else {
                throw usage("Drag requires a target element or at least one of --dx / --dy")
            }
            return .drag(
                DenSheetDragPayload(
                    source: parsed.positionals[0],
                    destination: parsed.positionals.count == 2 ? parsed.positionals[1] : nil,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    steps: steps
                )
            )

        case "mouse":
            guard let action = arguments.first else {
                throw usage("Usage: den board web mouse <move|down|up|click|wheel> ...")
            }
            let actionArguments = Array(arguments.dropFirst())
            switch action {
            case "move":
                guard actionArguments.count == 2,
                    let coordinateX = Double(actionArguments[0]),
                    let coordinateY = Double(actionArguments[1])
                else { throw usage("Usage: den board web mouse move <x> <y>") }
                return .mouse(.move(DenSheetMousePayload(coordX: coordinateX, coordY: coordinateY)))
            case "down":
                guard actionArguments.count <= 1 else {
                    throw usage("Usage: den board web mouse down [<button>]")
                }
                return .mouse(.down(DenSheetMousePayload(button: actionArguments.first)))
            case "up":
                guard actionArguments.count <= 1 else {
                    throw usage("Usage: den board web mouse up [<button>]")
                }
                return .mouse(.release(DenSheetMousePayload(button: actionArguments.first)))
            case "click":
                guard actionArguments.count >= 2 else {
                    throw usage("Usage: den board web mouse click <x> <y> [--button <left|right|middle>] [--count <n>]")
                }
                let clickArguments = Array(actionArguments.dropFirst(2))
                let parsed = try parseOptions(
                    clickArguments,
                    valued: ["--button", "--count"],
                    flags: []
                )
                guard parsed.positionals.isEmpty else {
                    throw usage("Usage: den board web mouse click <x> <y> [--button <left|right|middle>] [--count <n>]")
                }
                guard let coordinateX = Double(actionArguments[0]), let coordinateY = Double(actionArguments[1]) else {
                    throw usage("Usage: den board web mouse click <x> <y> [--button <left|right|middle>] [--count <n>]")
                }
                let button = parsed.values["--button"]
                let count = try parsed.values["--count"].map {
                    guard let value = Int($0) else { throw usage("Invalid value for --count: \($0)") }
                    return value
                }
                return .mouse(
                    .click(
                        DenSheetMousePayload(
                            coordX: coordinateX,
                            coordY: coordinateY,
                            button: button,
                            count: count
                        ))
                )
            case "wheel":
                guard actionArguments.count >= 1 else {
                    throw usage("Usage: den board web mouse wheel <dy> [--dx <dx>]")
                }
                let wheelArguments = Array(actionArguments.dropFirst())
                let parsed = try parseOptions(wheelArguments, valued: ["--dx"], flags: [])
                guard parsed.positionals.isEmpty else {
                    throw usage("Usage: den board web mouse wheel <dy> [--dx <dx>]")
                }
                guard let deltaY = Double(actionArguments[0]) else {
                    throw usage("Usage: den board web mouse wheel <dy> [--dx <dx>]")
                }
                return .mouse(
                    .wheel(
                        DenSheetMousePayload(
                            deltaX: try doubleValue("--dx", from: parsed.values),
                            deltaY: deltaY
                        ))
                )
            default:
                throw usage("Unknown mouse action: \(action)")
            }

        case "get":
            guard let kind = arguments.first else {
                throw usage("Usage: den board web get <text|value|attr|count|box> ...")
            }
            let values = Array(arguments.dropFirst())
            do {
                switch kind {
                case "text":
                    try requireArguments(2...2, "Usage: den board web get text <target>")
                    return .get(.text(try DenSheetGetTargetPayload(target: values[0])))
                case "value":
                    try requireArguments(2...2, "Usage: den board web get value <target>")
                    return .get(.value(try DenSheetGetTargetPayload(target: values[0])))
                case "attr":
                    try requireArguments(3...3, "Usage: den board web get attr <target> <attribute>")
                    return .get(
                        .attribute(try DenSheetGetAttributePayload(target: values[0], attribute: values[1]))
                    )
                case "count":
                    try requireArguments(2...2, "Usage: den board web get count <selector>")
                    return .get(.count(try DenSheetGetTargetPayload(target: values[0])))
                case "box":
                    try requireArguments(2...2, "Usage: den board web get box <target>")
                    return .get(.box(try DenSheetGetTargetPayload(target: values[0])))
                default:
                    throw usage("Unknown get kind: \(kind)")
                }
            } catch let error as ValidationError {
                throw error
            } catch {
                throw usage(error.localizedDescription)
            }

        case "is":
            guard arguments.count == 2 else {
                throw usage("Usage: den board web is <visible|enabled|checked> <target>")
            }
            do {
                let payload = try DenSheetStatePayload(target: arguments[1])
                switch arguments[0] {
                case "visible": return .isState(.visible(payload))
                case "enabled": return .isState(.enabled(payload))
                case "checked": return .isState(.checked(payload))
                default: throw usage("Unknown state: \(arguments[0])")
                }
            } catch {
                throw usage(error.localizedDescription)
            }

        case "interact":
            throw usage("Nested interact is not supported")

        default:
            throw ValidationError("Line \(line): Unknown or unsupported sheet action '\(commandName)'")
        }
    }

    static func splitCommands(_ line: String, line lineNumber: Int) throws -> [String] {
        var commands: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false

        for char in line {
            if isEscaped {
                current.append(char)
                isEscaped = false
                continue
            }
            if char == "\\" && !inSingleQuote {
                current.append(char)
                isEscaped = true
                continue
            }
            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                current.append(char)
                continue
            }
            if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                current.append(char)
                continue
            }
            if char == ";" && !inSingleQuote && !inDoubleQuote {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    commands.append(trimmed)
                }
                current = ""
                continue
            }
            current.append(char)
        }

        if isEscaped || inSingleQuote || inDoubleQuote {
            throw ValidationError("Line \(lineNumber): Unterminated quote or escape sequence")
        }

        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            commands.append(trimmed)
        }
        return commands
    }

    static func splitTokens(_ commandString: String, line lineNumber: Int) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false
        var hasToken = false

        for char in commandString {
            if isEscaped {
                current.append(char)
                hasToken = true
                isEscaped = false
                continue
            }
            if char == "\\" && !inSingleQuote {
                isEscaped = true
                continue
            }
            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                hasToken = true
                continue
            }
            if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                hasToken = true
                continue
            }
            if char.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if hasToken {
                    tokens.append(current)
                    current = ""
                    hasToken = false
                }
                continue
            }
            current.append(char)
            hasToken = true
        }

        if isEscaped || inSingleQuote || inDoubleQuote {
            throw ValidationError("Line \(lineNumber): Unterminated quote or escape sequence")
        }

        if hasToken {
            tokens.append(current)
        }
        return tokens
    }
}

struct SheetGetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Read information from the target Sheet",
        subcommands: [
            SheetGetTextCommand.self,
            SheetGetValueCommand.self,
            SheetGetAttributeCommand.self,
            SheetGetCountCommand.self,
            SheetGetBoxCommand.self,
        ]
    )
}

struct SheetGetBoxCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "box",
        abstract: "Get bounding box of an element")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .get(.box(try DenSheetGetTargetPayload(target: targetElement))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetGetTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Get text from an element")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .get(.text(try DenSheetGetTargetPayload(target: targetElement))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetGetValueCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "value",
        abstract: "Get an element value")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String
    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .get(.value(try DenSheetGetTargetPayload(target: targetElement))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetGetAttributeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attr",
        abstract: "Get an element attribute")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String
    @Argument(help: "Attribute name")
    var attribute: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .get(
                    .attribute(try DenSheetGetAttributePayload(target: targetElement, attribute: attribute))
                ),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetGetCountCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "count",
        abstract: "Count elements matching a selector")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "CSS selector")
    var selector: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .get(.count(try DenSheetGetTargetPayload(target: selector))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetIsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "is",
        abstract: "Check an element state",
        subcommands: [
            SheetIsVisibleCommand.self,
            SheetIsEnabledCommand.self,
            SheetIsCheckedCommand.self,
        ]
    )
}

struct SheetIsVisibleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "visible",
        abstract: "Check whether an element is visible")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .isState(.visible(try DenSheetStatePayload(target: targetElement))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetIsEnabledCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enabled",
        abstract: "Check whether an element is enabled")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .isState(.enabled(try DenSheetStatePayload(target: targetElement))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetIsCheckedCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "checked",
        abstract: "Check whether a checkbox is checked")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .isState(.checked(try DenSheetStatePayload(target: targetElement))),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetScreenshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture a PNG screenshot of the target Web Board")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Destination file path for PNG screenshot (optional)")
    var outputPath: String?

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .screenshot(DenSheetScreenshotPayload(outputPath: outputPath)),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetBackCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "back",
        abstract: "Navigate back in browsing history")

    @OptionGroup var target: SheetTargetOptions

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .back,
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetForwardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forward",
        abstract: "Navigate forward in browsing history")

    @OptionGroup var target: SheetTargetOptions

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .forward,
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetPressCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "press",
        abstract: "Dispatch key events (Enter, Escape, Tab, arrows) to the active element")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Key to press (e.g. Enter, Escape, Tab, ArrowDown, ArrowUp)")
    var key: String

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .press(DenSheetPressPayload(key: key)),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetScrollCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll the page or bring an element into view")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "Direction, pixel amount, element ref (@e1), or CSS selector (optional, defaults to down)")
    var directionOrTarget: String?

    func run() throws {
        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .scroll(DenSheetScrollPayload(directionOrTarget: directionOrTarget)),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}

struct SheetWaitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wait",
        abstract: "Wait for a DOM state, text, load state, URL, or JavaScript condition")

    @OptionGroup var target: SheetTargetOptions
    @Argument(help: "CSS selector or element reference (@e1)")
    var targetValue: String?
    @Option(name: .long, help: "State: attached, visible, hidden, or detached")
    var state: String?
    @Option(name: .long, help: "URL glob to wait for")
    var url: String?
    @Option(name: .long, help: "Text substring to wait for")
    var text: String?
    @Option(name: .customLong("load"), help: "Page load state: domcontentloaded, load, or networkidle")
    var loadState: String?
    @Option(name: .customLong("fn"), help: "JavaScript condition to wait for")
    var function: String?
    @Option(name: .long, help: "Timeout in seconds")
    var timeout: Double = 10

    func run() throws {
        let modes = [targetValue, url, text, loadState, function].compactMap { $0 }.count
        guard modes == 1 else {
            throw ValidationError("Provide exactly one of a selector/ref, --url, --text, --load, or --fn")
        }
        if targetValue == nil, state != nil {
            throw ValidationError("--state requires a selector or element reference")
        }
        if let targetValue, Double(targetValue) != nil {
            throw ValidationError("Duration waits are no longer supported; use --state, --url, --text, --load, or --fn")
        }
        if let state, !["attached", "visible", "hidden", "detached"].contains(state.lowercased()) {
            throw ValidationError("Invalid state: \(state)")
        }
        if let loadState,
            !["domcontentloaded", "load", "networkidle"].contains(loadState.lowercased())
        {
            throw ValidationError("Invalid load state: \(loadState)")
        }
        if let text, text.isEmpty {
            throw ValidationError("Text must not be empty")
        }
        if let function, function.isEmpty {
            throw ValidationError("JavaScript condition must not be empty")
        }
        guard timeout.isFinite, timeout >= 0 else {
            throw ValidationError("Timeout must be a finite non-negative number")
        }

        try DenIPCClient.execute(
            operation: DenIPCClient.sheetOperation(
                command: .wait(
                    DenSheetWaitPayload(
                        target: targetValue,
                        state: state,
                        url: url,
                        text: text,
                        loadState: loadState,
                        function: function,
                        timeout: timeout
                    )
                ),
                target: try DenIPCClient.boardTarget(target.target.boardID),
                snapshot: target.snapshotPayload
            ),
            options: target.target.common
        )
    }
}
