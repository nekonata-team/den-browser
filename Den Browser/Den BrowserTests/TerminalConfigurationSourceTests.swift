import Foundation
import GhosttyTerminal
import Testing

@testable import Den_Browser

@MainActor
struct TerminalConfigurationSourceTests {
    @Test func bundledThemeResolvesFromStandardConfig() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-terminal-config-\(UUID())", directoryHint: .isDirectory)
        let configDirectory = root.appending(path: "ghostty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "theme = Gruvbox Dark".write(
            to: configDirectory.appending(path: "config.ghostty"),
            atomically: true,
            encoding: .utf8)

        let theme = TerminalConfigurationSource.make(
            environment: ["XDG_CONFIG_HOME": root.path],
            arguments: []
        )
        .theme

        #expect(theme.dark.rendered.contains("palette = 1=#cc241d"))
    }

    @Test func bundledLightAndDarkThemesResolve() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-terminal-config-\(UUID())", directoryHint: .isDirectory)
        let configDirectory = root.appending(path: "ghostty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "theme = light:Gruvbox Light,dark:Gruvbox Dark".write(
            to: configDirectory.appending(path: "config.ghostty"),
            atomically: true,
            encoding: .utf8)

        let theme = TerminalConfigurationSource.make(
            environment: ["XDG_CONFIG_HOME": root.path],
            arguments: []
        )
        .theme

        #expect(theme.light.rendered.contains("background = fbf1c7"))
        #expect(theme.dark.rendered.contains("background = 282828"))
    }
}
