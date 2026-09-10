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
            SheetClickCommand.self,
            SheetFillCommand.self,
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
    @Flag(name: [.customShort("i"), .long], help: "Filter to interactive elements only")
    var interactive: Bool = false

    func run() throws {
        let args = interactive ? ["-i"] : []
        try DenIPCClient.execute(command: .sheet(.snapshot), args: args, options: target)
    }
}

struct SheetClickCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click an element by reference (@e1) or CSS selector")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector to click")
    var targetElement: String

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.click), args: [targetElement], options: target)
    }
}

struct SheetFillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fill",
        abstract: "Fill an input or textarea with text by reference or selector")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Element reference (@e1) or CSS selector to fill")
    var targetElement: String
    @Argument(parsing: .remaining, help: "Text value to fill into the input")
    var valueParts: [String]

    func run() throws {
        let value = valueParts.joined(separator: " ")
        guard !value.isEmpty else {
            throw ValidationError("Please provide a text value to fill")
        }
        try DenIPCClient.execute(command: .sheet(.fill), args: [targetElement, value], options: target)
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
        abstract: "Scroll the page (down, up, top, bottom, or pixel amount)")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Direction (down, up, top, bottom) or pixel amount (optional, defaults to down)")
    var direction: String?

    func run() throws {
        let args = direction.map { [$0] } ?? []
        try DenIPCClient.execute(command: .sheet(.scroll), args: args, options: target)
    }
}

struct SheetWaitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wait",
        abstract: "Wait for a duration in seconds (2, 0.5) or until a selector appears")

    @OptionGroup var target: BoardTargetOptions
    @Argument(help: "Duration in seconds (e.g. 2, 0.5) or CSS selector/ref (@e1)")
    var targetValue: String

    func run() throws {
        try DenIPCClient.execute(command: .sheet(.wait), args: [targetValue], options: target)
    }
}
