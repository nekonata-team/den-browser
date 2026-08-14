import Foundation
import GhosttyKit
import GhosttyTerminal
import Testing

@testable import Den_Browser

@MainActor
struct TerminalConfigurationSourceTests {
    @Test func zellijLaunchCommandsUseWelcomeOrNamedSession() {
        #expect(
            ZellijLaunchCommand.command(
                sessionName: nil,
                executablePath: "/opt/homebrew/bin/zellij")
                == "'/opt/homebrew/bin/zellij' -l welcome"
        )
        #expect(
            ZellijLaunchCommand.command(
                sessionName: "project's shell",
                executablePath: "/opt/homebrew/bin/zellij")
                == "'/opt/homebrew/bin/zellij' attach --create 'project'\\''s shell'"
        )
        #expect(ZellijLaunchCommand.command(sessionName: nil, executablePath: "zellij") == nil)
    }

    @Test func zmxLaunchCommandsUseNamedSession() {
        #expect(
            ZmxLaunchCommand.command(
                sessionName: "project's shell",
                executablePath: "/opt/homebrew/bin/zmx")
                == "'/opt/homebrew/bin/zmx' attach 'project'\\''s shell'"
        )
        #expect(ZmxLaunchCommand.command(sessionName: "", executablePath: "/opt/homebrew/bin/zmx") == nil)
        #expect(ZmxLaunchCommand.command(sessionName: " ", executablePath: "/opt/homebrew/bin/zmx") == nil)
        #expect(ZmxLaunchCommand.command(sessionName: "project", executablePath: "zmx") == nil)
    }

    @Test func zellijCommandOverridesUserCommandWithoutShellInput() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-terminal-command-\(UUID())", directoryHint: .isDirectory)
        let configDirectory = root.appending(path: "ghostty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "command = /bin/zsh -f\nfont-size = 14".write(
            to: configDirectory.appending(path: "config.ghostty"),
            atomically: true,
            encoding: .utf8)

        let resolution = TerminalConfigurationSource.make(
            environment: ["XDG_CONFIG_HOME": root.path],
            arguments: [],
            commandOverride: "'/opt/homebrew/bin/zellij' -l welcome")

        guard case let .generated(contents) = resolution.configSource else {
            Issue.record("Expected a generated Ghostty config")
            return
        }
        #expect(!contents.contains("command = /bin/zsh -f"))
        #expect(contents.contains("command = '/opt/homebrew/bin/zellij' -l welcome"))
        #expect(contents.contains("font-size = 14"))
    }

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

    @Test func userGhosttyConfigurationIsForwardedAndValid() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-terminal-config-\(UUID())", directoryHint: .isDirectory)
        let configDirectory = root.appending(path: "ghostty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        theme = Gruvbox Dark
        font-size = 14
        macos-option-as-alt = left
        keybind = alt+left=unbind
        keybind = alt+right=text:\\x1b[1;3C
        """.write(
            to: configDirectory.appending(path: "config.ghostty"),
            atomically: true,
            encoding: .utf8)

        let resolution = TerminalConfigurationSource.make(
            environment: ["XDG_CONFIG_HOME": root.path],
            arguments: [])

        guard case let .generated(contents) = resolution.configSource else {
            Issue.record("Expected a generated Ghostty config")
            return
        }
        #expect(contents.contains("font-size = 14"))
        #expect(contents.contains("macos-option-as-alt = left"))
        #expect(contents.contains("keybind = alt+left=unbind"))
        #expect(contents.contains("keybind = alt+right=text:\\x1b[1;3C"))
        #expect(!contents.contains("theme = Gruvbox Dark"))
        #expect(resolution.theme.dark.rendered.contains("background = 282828"))

        let generatedURL = root.appending(path: "generated.conf")
        try contents.write(to: generatedURL, atomically: true, encoding: .utf8)

        #expect(ghostty_init(0, nil) == GHOSTTY_SUCCESS)
        guard let config = ghostty_config_new() else {
            Issue.record("ghostty_config_new returned nil")
            return
        }
        defer { ghostty_config_free(config) }

        ghostty_config_load_file(config, generatedURL.path)
        ghostty_config_finalize(config)
        #expect(ghostty_config_diagnostics_count(config) == 0)

        var left = ghostty_input_key_s()
        left.action = GHOSTTY_ACTION_PRESS
        left.mods = GHOSTTY_MODS_ALT
        left.keycode = 123
        #expect(!ghostty_config_key_is_binding(config, left))

        var right = left
        right.keycode = 124
        #expect(ghostty_config_key_is_binding(config, right))
    }
}
