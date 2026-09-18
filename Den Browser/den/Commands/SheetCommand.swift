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
            SheetFillCommand.self,
            SheetDragCommand.self,
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
        try DenIPCClient.execute(command: .sheet(.open), args: [url], options: target)
    }
}

struct SheetURLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "url",
        abstract: "Print Current Sheet URL of the target Web Board")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.url), args: [], options: target)
    }
}

struct SheetReloadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reload",
        abstract: "Reload Current Sheet in the target Web Board")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.reload), args: [], options: target)
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
        try DenIPCClient.execute(command: .sheet(.eval), args: [script], options: target)
    }
}

struct SheetTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Print visible text from the target Web Board")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.text), args: [], options: target)
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
        var args = full ? ["--full"] : ["-i"]
        if let within {
            args.append(contentsOf: ["--within", within])
        }
        try DenIPCClient.execute(command: .sheet(.snapshot), args: args, options: target)
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
        var args = [selector]
        if visible { args.append("--visible") }
        if all { args.append("--all") }
        if let fields {
            args.append(contentsOf: ["--fields", fields])
        }
        try DenIPCClient.execute(command: .sheet(.query), args: args, options: target)
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
        var args = targetElement.map { [$0] } ?? []
        if let role {
            args.append(contentsOf: ["--role", role])
        }
        if let name {
            args.append(contentsOf: ["--name", name])
        }
        if exact {
            args.append("--exact")
        }
        if newBoard {
            args.append("--new-board")
        }
        if focus {
            args.append("--focus")
        }
        try DenIPCClient.execute(command: .sheet(.click), args: args, options: target)
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
        try DenIPCClient.execute(command: .sheet(.fill), args: [targetElement, value], options: target)
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
        var args = [source]
        if let destination {
            args.append(destination)
        }
        if let deltaX {
            args.append(contentsOf: ["--dx", String(deltaX)])
        }
        if let deltaY {
            args.append(contentsOf: ["--dy", String(deltaY)])
        }
        if steps != 5 {
            args.append(contentsOf: ["--steps", String(steps)])
        }
        try DenIPCClient.execute(command: .sheet(.drag), args: args, options: target)
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
              fill <ref|selector> <text>        Fill an input, textarea, or editable element with text
              drag <src> [<tgt>] [--dx] [--dy]  Drag an element to a target or relative offset
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
        let encoded = try JSONEncoder().encode(steps)
        guard let jsonString = String(data: encoded, encoding: .utf8) else {
            throw ValidationError("Failed to encode script actions")
        }

        var args = [jsonString]
        if full { args.append("--full") }
        try DenIPCClient.execute(command: .sheet(.interact), args: args, options: target)
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
                guard let sheetCommand = DenIPCCommand.Sheet(rawValue: commandName),
                    sheetCommand != .interact
                else {
                    throw ValidationError(
                        "Line \(lineNumber): Unknown or unsupported sheet action '\(commandName)'")
                }
                steps.append(DenSheetInteractStep(line: lineNumber, text: commandString, args: tokens))
            }
        }
        return steps
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
        ]
    )
}

struct SheetGetTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Get text from an element")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.get), args: ["text", targetElement], options: target)
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
        try DenIPCClient.execute(command: .sheet(.get), args: ["value", targetElement], options: target)
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
            command: .sheet(.get),
            args: ["attr", targetElement, attribute],
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
        try DenIPCClient.execute(command: .sheet(.get), args: ["count", selector], options: target)
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
        try DenIPCClient.execute(command: .sheet(.isState), args: ["visible", targetElement], options: target)
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
        try DenIPCClient.execute(command: .sheet(.isState), args: ["enabled", targetElement], options: target)
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
        try DenIPCClient.execute(command: .sheet(.isState), args: ["checked", targetElement], options: target)
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
        let args = outputPath.map { [$0] } ?? []
        try DenIPCClient.execute(command: .sheet(.screenshot), args: args, options: target)
    }
}

struct SheetBackCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "back",
        abstract: "Navigate back in browsing history")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.back), args: [], options: target)
    }
}

struct SheetForwardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forward",
        abstract: "Navigate forward in browsing history")

    @OptionGroup var target: BoardTargetOptions

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.forward), args: [], options: target)
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
        try DenIPCClient.execute(command: .sheet(.press), args: [key], options: target)
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
        let args = directionOrTarget.map { [$0] } ?? []
        try DenIPCClient.execute(command: .sheet(.scroll), args: args, options: target)
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

        var args: [String] = []
        if let targetValue {
            args.append(targetValue)
        }
        if let state {
            args.append(contentsOf: ["--state", state])
        }
        if let url {
            args.append(contentsOf: ["--url", url])
        }
        if let text {
            args.append(contentsOf: ["--text", text])
        }
        if let loadState {
            args.append(contentsOf: ["--load", loadState])
        }
        if let function {
            args.append(contentsOf: ["--fn", function])
        }
        args.append(contentsOf: ["--timeout", String(timeout)])
        try DenIPCClient.execute(command: .sheet(.wait), args: args, options: target)
    }
}
