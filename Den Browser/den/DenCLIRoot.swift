import ArgumentParser
import Foundation

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct DenCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "den",
        abstract: "Control and inspect Den Browser from terminal or external shell",
        version: appVersion,
        subcommands: [
            HealthCommand.self,
            SheetCommand.self,
            BoardCommand.self,
            InspectionCommand.self,
            DeskCommand.self,
            DrawerCommand.self,
            TerminalCommand.self,
            ProfileCommand.self,
            MCPCommand.self,
        ]
    )

    private static var appVersion: String {
        let versionKey = "CFBundleShortVersionString"
        if let version = Bundle.main.infoDictionary?[versionKey] as? String {
            return version
        }

        guard var bundleURL = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            return "unknown"
        }

        while bundleURL.pathExtension != "app" {
            let parentURL = bundleURL.deletingLastPathComponent()
            guard parentURL != bundleURL else { return "unknown" }
            bundleURL = parentURL
        }

        return Bundle(url: bundleURL)?.infoDictionary?[versionKey] as? String ?? "unknown"
    }
}
