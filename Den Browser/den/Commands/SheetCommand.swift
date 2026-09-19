import ArgumentParser
import Foundation

struct SheetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sheet",
        abstract: "Inspect and control Sheets in Web Boards",
        subcommands: [
            SheetOpenCommand.self,
            SheetURLCommand.self,
            SheetReloadCommand.self,
            SheetBackCommand.self,
            SheetForwardCommand.self,
            SheetPressCommand.self,
            SheetScrollCommand.self,
            SheetWaitCommand.self,
            SheetEvalCommand.self,
            SheetTextCommand.self,
            SheetSnapshotCommand.self,
            SheetQueryCommand.self,
            SheetGetCommand.self,
            SheetIsCommand.self,
            SheetClickCommand.self,
            SheetDblclickCommand.self,
            SheetFocusCommand.self,
            SheetFillCommand.self,
            SheetTypeCommand.self,
            SheetDragCommand.self,
            SheetMouseCommand.self,
            SheetInteractCommand.self,
            SheetScreenshotCommand.self,
        ]
    )
}

struct SheetOpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Navigate Current Sheet in the target Web Board to a URL or search query")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "URL or search query to open") var url: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.open),
            payload: .sheet(.open(DenSheetOpenPayload(url: url))),
            options: target
        )
    }
}

struct SheetURLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "url",
        abstract: "Print Current Sheet URL of the target Web Board")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.url), options: target)
    }
}

struct SheetReloadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Reload Current Sheet in the target Web Board")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.reload), options: target)
    }
}

struct SheetEvalCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eval",
        abstract: "Evaluate JavaScript in the target Web Board")

    @OptionGroup var target: BoardTargetOptions
    @Argument(parsing: .remaining, help: "JavaScript code to evaluate") var scriptParts: [String]

    func run() throws {
        let script = scriptParts.joined(separator: " ")
        guard !script.isEmpty else {
            throw ValidationError("Please provide JavaScript code to evaluate")
        }
        try DenIPCClient.execute(
            command: .sheet(.eval),
            payload: .sheet(.eval(DenSheetEvalPayload(script: script))),
            options: target
        )
    }
}

struct SheetTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Print visible text from the target Web Board")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.text), options: target)
    }
}

struct SheetSnapshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Extract semantic DOM tree with short references (@e1, @e2)")

    @OptionGroup var target: BoardTargetOptions
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
            command: .sheet(.snapshot),
            payload: .sheet(.snapshot(DenSheetSnapshotPayload(full: full, within: within))),
            options: target
        )
    }
}

struct SheetQueryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Inspect matching DOM elements")

    @OptionGroup var target: BoardTargetOptions
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
            command: .sheet(.query),
            payload: .sheet(
                .query(
                    DenSheetQueryPayload(
                        selector: selector,
                        visible: visible,
                        all: all,
                        fields: fields
                    )
                )
            ),
            options: target
        )
    }
}

struct SheetClickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click an element by reference (@e1) or CSS selector")

    @OptionGroup var target: BoardTargetOptions
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
            command: .sheet(.click),
            payload: .sheet(
                .click(
                    DenSheetClickPayload(
                        target: targetElement,
                        role: role,
                        name: name,
                        exact: exact,
                        newBoard: newBoard,
                        focus: focus
                    )
                )
            ),
            options: target
        )
    }
}

struct SheetDblclickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dblclick",
        abstract: "Double-click an element by reference (@e1) or CSS selector"
    )

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector to double-click")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.dblclick),
            payload: .sheet(.dblclick(DenSheetElementTargetPayload(target: targetElement))),
            options: target
        )
    }
}

struct SheetFocusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Focus an element by reference (@e1) or CSS selector"
    )

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector to focus")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.focus),
            payload: .sheet(.focus(DenSheetElementTargetPayload(target: targetElement))),
            options: target
        )
    }
}

struct SheetFillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fill",
        abstract: "Fill an input, textarea, or editable element with text by reference or selector")

    @OptionGroup var target: BoardTargetOptions
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
            command: .sheet(.fill),
            payload: .sheet(.fill(DenSheetFillPayload(target: targetElement, value: value))),
            options: target
        )
    }
}

struct SheetTypeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into an element by reference/selector or into the currently focused element"
    )

    @OptionGroup var target: BoardTargetOptions
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
            command: .sheet(.type),
            payload: .sheet(.type(payload)),
            options: target
        )
    }
}

struct SheetDragCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drag",
        abstract: "Drag an element by reference (@e1) or selector to another element or relative offset"
    )

    @OptionGroup var target: BoardTargetOptions
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
            command: .sheet(.drag),
            payload: .sheet(
                .drag(
                    DenSheetDragPayload(
                        source: source,
                        destination: destination,
                        deltaX: deltaX,
                        deltaY: deltaY,
                        steps: steps
                    )
                )
            ),
            options: target
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

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "X coordinate in viewport pixels") var coordX: Double
    @Argument(help: "Y coordinate in viewport pixels") var coordY: Double

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.mouse(.move)),
            payload: .sheet(.mouse(DenSheetMousePayload(coordX: coordX, coordY: coordY))),
            options: target
        )
    }
}

struct SheetMouseDownCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "down",
        abstract: "Press mouse button down"
    )

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Button to press (left, right, middle; default: left)")
    var button: String?

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.mouse(.down)),
            payload: .sheet(.mouse(DenSheetMousePayload(button: button))),
            options: target
        )
    }
}

struct SheetMouseUpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up",
        abstract: "Release mouse button"
    )

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Button to release (left, right, middle; default: left)")
    var button: String?

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.mouse(.release)),
            payload: .sheet(.mouse(DenSheetMousePayload(button: button))),
            options: target
        )
    }
}

struct SheetMouseClickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click at viewport coordinates"
    )

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "X coordinate in viewport pixels") var coordX: Double
    @Argument(help: "Y coordinate in viewport pixels") var coordY: Double
    @Option(name: .long, help: "Mouse button (left, right, middle; default: left)")
    var button: String?
    @Option(name: .long, help: "Click count (1 for click, 2 for double-click; default: 1)")
    var count: Int?

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.mouse(.click)),
            payload: .sheet(
                .mouse(
                    DenSheetMousePayload(
                        coordX: coordX,
                        coordY: coordY,
                        button: button,
                        count: count
                    )
                )
            ),
            options: target
        )
    }
}

struct SheetMouseWheelCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wheel",
        abstract: "Scroll mouse wheel"
    )

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Vertical scroll delta in pixels") var deltaY: Double
    @Option(name: .customLong("dx"), help: "Horizontal scroll delta in pixels (default: 0)")
    var deltaX: Double?

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.mouse(.wheel)),
            payload: .sheet(.mouse(DenSheetMousePayload(deltaX: deltaX, deltaY: deltaY))),
            options: target
        )
    }
}

struct SheetInteractCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interact",
        abstract: "Run multiple Sheet actions from a script, file, or stdin and return a final semantic snapshot",
        discussion: """
            Executes a series of Sheet actions line-by-line and returns the final semantic snapshot.
            Each line or semicolon-separated statement uses the same syntax as 'den sheet <subcommand>'.

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
              open <url>                        Navigate to a URL
              reload                            Reload current Sheet
              back / forward                    Navigate history
              eval <javascript>                 Evaluate JavaScript code

            Examples:
              den sheet interact "click @e1; fill @e2 Hello; press Enter"
              den sheet interact << 'EOF'
              click @e1
              fill @e2 "query text"
              press Enter
              wait --load networkidle
              screenshot /tmp/result.png
              EOF
              den sheet interact path/to/script.den
            """)

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Script text, script file path, or - for stdin (defaults to stdin if piped)")
    var scriptOrPath: String?
    @Flag(name: .long, help: "Include the full semantic tree in the final snapshot")
    var full: Bool = false

    func run() throws {
        let script = try readScript()
        let steps = try DenSheetScriptParser.parse(script)
        guard !steps.isEmpty else {
            throw ValidationError("Script contains no valid actions")
        }
        let payload = DenSheetInteractPayload(steps: steps, full: full)
        try DenIPCClient.execute(
            command: .sheet(.interact),
            payload: .sheet(.interact(payload)),
            options: target
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
                let action = try payload(
                    for: commandName,
                    arguments: Array(tokens.dropFirst()),
                    line: lineNumber
                )
                steps.append(
                    DenSheetInteractStep(
                        line: lineNumber,
                        text: commandString,
                        command: action.command,
                        payload: action.payload
                    )
                )
            }
        }
        return steps
    }

    private static func payload(
        for commandName: String,
        arguments: [String],
        line: Int
    ) throws -> (command: DenIPCCommand.Sheet, payload: DenSheetPayload?) {
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
            return (.url, nil)

        case "reload":
            try requireArguments(0...0, "reload does not accept arguments")
            return (.reload, nil)

        case "text":
            try requireArguments(0...0, "text does not accept arguments")
            return (.text, nil)

        case "back":
            try requireArguments(0...0, "back does not accept arguments")
            return (.back, nil)

        case "forward":
            try requireArguments(0...0, "forward does not accept arguments")
            return (.forward, nil)

        case "open":
            try requireArguments(1...1, "Usage: den sheet open <url>")
            return (.open, .open(DenSheetOpenPayload(url: arguments[0])))

        case "eval":
            guard !arguments.isEmpty else { throw usage("Usage: den sheet eval <javascript>") }
            return (.eval, .eval(DenSheetEvalPayload(script: arguments.joined(separator: " "))))

        case "press":
            try requireArguments(1...1, "Usage: den sheet press <key>")
            return (.press, .press(DenSheetPressPayload(key: arguments[0])))

        case "scroll":
            try requireArguments(0...1, "Usage: den sheet scroll [<direction|amount|target>]")
            return (.scroll, .scroll(DenSheetScrollPayload(directionOrTarget: arguments.first)))

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
            guard parsed.positionals.count <= 1 else { throw usage("Usage: den sheet wait <selector|ref> [options]") }
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
            return (
                .wait,
                .wait(
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
            )

        case "screenshot":
            try requireArguments(0...1, "Usage: den sheet screenshot [<output-path>]")
            return (.screenshot, .screenshot(DenSheetScreenshotPayload(outputPath: arguments.first)))

        case "snapshot":
            let parsed = try parseOptions(arguments, valued: ["--within"], flags: ["--full", "--interactive", "-i"])
            guard parsed.positionals.isEmpty else {
                throw usage("Usage: den sheet snapshot [--interactive|--full] [--within <selector|ref>]")
            }
            let interactive = parsed.flags.contains("--interactive") || parsed.flags.contains("-i")
            guard !(parsed.flags.contains("--full") && interactive) else {
                throw usage("Please choose either --interactive or --full")
            }
            return (
                .snapshot,
                .snapshot(
                    DenSheetSnapshotPayload(
                        full: parsed.flags.contains("--full"),
                        within: parsed.values["--within"]
                    )
                )
            )

        case "query":
            let parsed = try parseOptions(arguments, valued: ["--fields"], flags: ["--visible", "--all"])
            guard parsed.positionals.count == 1, !parsed.positionals[0].isEmpty else {
                throw usage("Usage: den sheet query <selector>")
            }
            return (
                .query,
                .query(
                    DenSheetQueryPayload(
                        selector: parsed.positionals[0],
                        visible: parsed.flags.contains("--visible"),
                        all: parsed.flags.contains("--all"),
                        fields: parsed.values["--fields"]
                    )
                )
            )

        case "click":
            let parsed = try parseOptions(
                arguments,
                valued: ["--role", "--name"],
                flags: ["--exact", "--new-board", "--focus"]
            )
            guard parsed.positionals.count <= 1 else {
                throw usage("Usage: den sheet click <@ref|selector> or --role <role> --name <name>")
            }
            let target = parsed.positionals.first
            let role = parsed.values["--role"]
            let name = parsed.values["--name"]
            guard target != nil || (role != nil && name != nil) else {
                throw usage("Usage: den sheet click <@ref|selector> or --role <role> --name <name>")
            }
            guard target == nil || (role == nil && name == nil) else {
                throw usage("Provide either a selector/ref or --role and --name, not both")
            }
            return (
                .click,
                .click(
                    DenSheetClickPayload(
                        target: target,
                        role: role,
                        name: name,
                        exact: parsed.flags.contains("--exact"),
                        newBoard: parsed.flags.contains("--new-board"),
                        focus: parsed.flags.contains("--focus")
                    )
                )
            )

        case "dblclick", "focus":
            try requireArguments(1...1, "Usage: den sheet \(commandName) <@ref|selector>")
            let payload = DenSheetElementTargetPayload(target: arguments[0])
            if commandName == "dblclick" {
                return (.dblclick, .dblclick(payload))
            }
            return (.focus, .focus(payload))

        case "fill":
            guard arguments.count >= 2 else { throw usage("Usage: den sheet fill <@ref|selector> <value>") }
            return (
                .fill,
                .fill(
                    DenSheetFillPayload(target: arguments[0], value: arguments.dropFirst().joined(separator: " "))
                )
            )

        case "type":
            guard !arguments.isEmpty else { throw usage("Usage: den sheet type [<@ref|selector>] <text>") }
            let payload =
                arguments.count == 1
                ? DenSheetTypePayload(target: nil, text: arguments[0])
                : DenSheetTypePayload(target: arguments[0], text: arguments.dropFirst().joined(separator: " "))
            return (.type, .type(payload))

        case "drag":
            let parsed = try parseOptions(arguments, valued: ["--dx", "--dy", "--steps"], flags: [])
            guard parsed.positionals.count >= 1, parsed.positionals.count <= 2 else {
                throw usage("Usage: den sheet drag <source> [<target>] [--dx <dx>] [--dy <dy>] [--steps <steps>]")
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
            return (
                .drag,
                .drag(
                    DenSheetDragPayload(
                        source: parsed.positionals[0],
                        destination: parsed.positionals.count == 2 ? parsed.positionals[1] : nil,
                        deltaX: deltaX,
                        deltaY: deltaY,
                        steps: steps
                    )
                )
            )

        case "mouse":
            guard let action = arguments.first else {
                throw usage("Usage: den sheet mouse <move|down|up|click|wheel> ...")
            }
            let actionArguments = Array(arguments.dropFirst())
            switch action {
            case "move":
                guard actionArguments.count == 2,
                    let coordinateX = Double(actionArguments[0]),
                    let coordinateY = Double(actionArguments[1])
                else { throw usage("Usage: den sheet mouse move <x> <y>") }
                return (
                    .mouse(.move),
                    .mouse(DenSheetMousePayload(coordX: coordinateX, coordY: coordinateY))
                )
            case "down":
                guard actionArguments.count <= 1 else {
                    throw usage("Usage: den sheet mouse down [<button>]")
                }
                return (.mouse(.down), .mouse(DenSheetMousePayload(button: actionArguments.first)))
            case "up":
                guard actionArguments.count <= 1 else {
                    throw usage("Usage: den sheet mouse up [<button>]")
                }
                return (.mouse(.release), .mouse(DenSheetMousePayload(button: actionArguments.first)))
            case "click":
                guard actionArguments.count >= 2 else {
                    throw usage("Usage: den sheet mouse click <x> <y> [--button <left|right|middle>] [--count <n>]")
                }
                let clickArguments = Array(actionArguments.dropFirst(2))
                let parsed = try parseOptions(
                    clickArguments,
                    valued: ["--button", "--count"],
                    flags: []
                )
                guard parsed.positionals.isEmpty else {
                    throw usage("Usage: den sheet mouse click <x> <y> [--button <left|right|middle>] [--count <n>]")
                }
                guard let coordinateX = Double(actionArguments[0]), let coordinateY = Double(actionArguments[1]) else {
                    throw usage("Usage: den sheet mouse click <x> <y> [--button <left|right|middle>] [--count <n>]")
                }
                let button = parsed.values["--button"]
                let count = try parsed.values["--count"].map {
                    guard let value = Int($0) else { throw usage("Invalid value for --count: \($0)") }
                    return value
                }
                return (
                    .mouse(.click),
                    .mouse(
                        DenSheetMousePayload(
                            coordX: coordinateX,
                            coordY: coordinateY,
                            button: button,
                            count: count
                        )
                    )
                )
            case "wheel":
                guard actionArguments.count >= 1 else {
                    throw usage("Usage: den sheet mouse wheel <dy> [--dx <dx>]")
                }
                let wheelArguments = Array(actionArguments.dropFirst())
                let parsed = try parseOptions(wheelArguments, valued: ["--dx"], flags: [])
                guard parsed.positionals.isEmpty else {
                    throw usage("Usage: den sheet mouse wheel <dy> [--dx <dx>]")
                }
                guard let deltaY = Double(actionArguments[0]) else {
                    throw usage("Usage: den sheet mouse wheel <dy> [--dx <dx>]")
                }
                return (
                    .mouse(.wheel),
                    .mouse(
                        DenSheetMousePayload(
                            deltaX: try doubleValue("--dx", from: parsed.values),
                            deltaY: deltaY
                        )
                    )
                )
            default:
                throw usage("Unknown mouse action: \(action)")
            }

        case "get":
            guard let kind = arguments.first else {
                throw usage("Usage: den sheet get <text|value|attr|count|box> ...")
            }
            let values = Array(arguments.dropFirst())
            do {
                switch kind {
                case "text":
                    try requireArguments(2...2, "Usage: den sheet get text <target>")
                    return (.get(.text), .get(try DenSheetGetPayload(target: values[0])))
                case "value":
                    try requireArguments(2...2, "Usage: den sheet get value <target>")
                    return (.get(.value), .get(try DenSheetGetPayload(target: values[0])))
                case "attr":
                    try requireArguments(3...3, "Usage: den sheet get attr <target> <attribute>")
                    return (
                        .get(.attribute),
                        .get(try DenSheetGetPayload(target: values[0], attribute: values[1]))
                    )
                case "count":
                    try requireArguments(2...2, "Usage: den sheet get count <selector>")
                    return (.get(.count), .get(try DenSheetGetPayload(target: values[0])))
                case "box":
                    try requireArguments(2...2, "Usage: den sheet get box <target>")
                    return (.get(.box), .get(try DenSheetGetPayload(target: values[0])))
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
                throw usage("Usage: den sheet is <visible|enabled|checked> <target>")
            }
            guard let state = DenIPCCommand.IsState(rawValue: arguments[0]) else {
                throw usage("Unknown state: \(arguments[0])")
            }
            do {
                return (.isState(state), .isState(try DenSheetStatePayload(target: arguments[1])))
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

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.get(.box)),
            payload: .sheet(.get(try DenSheetGetPayload(target: targetElement))),
            options: target
        )
    }
}

struct SheetGetTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Get text from an element")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.get(.text)),
            payload: .sheet(.get(try DenSheetGetPayload(target: targetElement))),
            options: target
        )
    }
}

struct SheetGetValueCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "value",
        abstract: "Get an element value")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String
    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.get(.value)),
            payload: .sheet(.get(try DenSheetGetPayload(target: targetElement))),
            options: target
        )
    }
}

struct SheetGetAttributeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attr",
        abstract: "Get an element attribute")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String
    @Argument(help: "Attribute name")
    var attribute: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.get(.attribute)),
            payload: .sheet(
                .get(
                    try DenSheetGetPayload(target: targetElement, attribute: attribute)
                )),
            options: target
        )
    }
}

struct SheetGetCountCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "count",
        abstract: "Count elements matching a selector")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "CSS selector")
    var selector: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.get(.count)),
            payload: .sheet(.get(try DenSheetGetPayload(target: selector))),
            options: target
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

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.isState(.visible)),
            payload: .sheet(.isState(try DenSheetStatePayload(target: targetElement))),
            options: target
        )
    }
}

struct SheetIsEnabledCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enabled",
        abstract: "Check whether an element is enabled")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.isState(.enabled)),
            payload: .sheet(.isState(try DenSheetStatePayload(target: targetElement))),
            options: target
        )
    }
}

struct SheetIsCheckedCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "checked",
        abstract: "Check whether a checkbox is checked")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.isState(.checked)),
            payload: .sheet(.isState(try DenSheetStatePayload(target: targetElement))),
            options: target
        )
    }
}

struct SheetScreenshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture a PNG screenshot of the target Web Board")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Destination file path for PNG screenshot (optional)")
    var outputPath: String?

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.screenshot),
            payload: .sheet(.screenshot(DenSheetScreenshotPayload(outputPath: outputPath))),
            options: target
        )
    }
}

struct SheetBackCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "back",
        abstract: "Navigate back in browsing history")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.back), options: target)
    }
}

struct SheetForwardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forward",
        abstract: "Navigate forward in browsing history")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.forward), options: target)
    }
}

struct SheetPressCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "press",
        abstract: "Dispatch key events (Enter, Escape, Tab, arrows) to the active element")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Key to press (e.g. Enter, Escape, Tab, ArrowDown, ArrowUp)")
    var key: String

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.press),
            payload: .sheet(.press(DenSheetPressPayload(key: key))),
            options: target
        )
    }
}

struct SheetScrollCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll the page or bring an element into view")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Direction, pixel amount, element ref (@e1), or CSS selector (optional, defaults to down)")
    var directionOrTarget: String?

    func run() throws {
        try DenIPCClient.execute(
            command: .sheet(.scroll),
            payload: .sheet(.scroll(DenSheetScrollPayload(directionOrTarget: directionOrTarget))),
            options: target
        )
    }
}

struct SheetWaitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wait",
        abstract: "Wait for a DOM state, text, load state, URL, or JavaScript condition")

    @OptionGroup var target: BoardTargetOptions
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
            command: .sheet(.wait),
            payload: .sheet(
                .wait(
                    DenSheetWaitPayload(
                        target: targetValue,
                        state: state,
                        url: url,
                        text: text,
                        loadState: loadState,
                        function: function,
                        timeout: timeout
                    )
                )
            ),
            options: target
        )
    }
}
