import Foundation
import GhosttyKit
import GhosttyTerminal
import Testing

@testable import Den_Browser

@MainActor
struct TerminalConfigurationSourceTests {
    @Test func terminalCommandRunnerDrainsLargeOutputBeforeWaiting() throws {
        let output = String(repeating: "x", count: 100_000)
        let result = try #require(
            ProcessTerminalCommandRunner().run(
                executablePath: "/usr/bin/printf",
                arguments: [output]))

        #expect(result.terminationStatus == 0)
        #expect(result.standardOutput == output)
    }

    @Test func zellijLaunchCommandsUseWelcomeOrNamedSession() {
        #expect(
            ZellijClient(executablePath: "/opt/homebrew/bin/zellij")
                .launchCommand(sessionName: nil)
                == "'/opt/homebrew/bin/zellij' -l welcome"
        )
        #expect(
            ZellijClient(executablePath: "/opt/homebrew/bin/zellij")
                .launchCommand(sessionName: "project's shell")
                == "'/opt/homebrew/bin/zellij' attach --create 'project'\\''s shell'"
        )
        #expect(ZellijClient(executablePath: "zellij").launchCommand(sessionName: nil) == nil)
    }

    @Test func zmxLaunchCommandsUseNamedSession() {
        #expect(
            ZmxClient(executablePath: "/opt/homebrew/bin/zmx")
                .launchCommand(sessionName: "project's shell")
                == "'/opt/homebrew/bin/zmx' attach 'project'\\''s shell'"
        )
        #expect(ZmxClient(executablePath: "/opt/homebrew/bin/zmx").launchCommand(sessionName: "") == nil)
        #expect(ZmxClient(executablePath: "/opt/homebrew/bin/zmx").launchCommand(sessionName: " ") == nil)
        #expect(ZmxClient(executablePath: "zmx").launchCommand(sessionName: "project") == nil)
    }

    @Test func zmxChildLaunchCommandInitializesRootLabel() throws {
        let command = try #require(
            ZmxClient(executablePath: "/opt/homebrew/bin/zmx")
                .launchCommand(sessionName: "den-vi", rootSessionName: "den"))

        #expect(command.contains("attach 'den-vi' /bin/sh -lc"))
        #expect(command.contains("den.root=den"))
    }

    @Test func zmxClientReadsActiveSessionsAndRootLabel() throws {
        let client = ZmxClient(
            executablePath: "/opt/homebrew/bin/zmx",
            commandRunner: StubTerminalCommandRunner(
                responses: [
                    ["list", "--short"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "name=den-vi\tstatus=running\nplain-session\n"),
                    ["get", "den-vi", "den.root"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: " den \n"),
                ]))

        #expect(client.activeSessionNames() == ["den-vi", "plain-session"])
        #expect(client.rootSessionName(for: "den-vi") == "den")
    }

    @Test func zmxClientReportsForegroundAndIdleProcesses() throws {
        let client = ZmxClient(
            executablePath: "/opt/homebrew/bin/zmx",
            commandRunner: StubTerminalCommandRunner(
                responses: [
                    ["list"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "name=den\tpid=100\n"
                            + "name=den-idle\tpid=300\n"
                            + "name=den-web\tpid=500\n"
                            + "name=den-unknown\tpid=999\n"),
                    ["-axo", "pid=,ppid=,pgid=,tpgid=,command="]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "100 1 100 200 /bin/zsh\n"
                            + "200 100 200 200 /opt/codex\n"
                            + "201 200 200 200 /opt/node\n"
                            + "300 1 300 300 /bin/zsh\n"
                            + "500 1 500 600 /bin/zsh\n"
                            + "600 1 600 600 /opt/just web dev\n"
                            + "601 600 600 600 pnpm dev\n"
                            + "602 601 600 600 node astro dev\n"),
                ]))

        let snapshot = try #require(client.sessionSnapshot())
        #expect(
            snapshot.processNames == [
                "den": "codex",
                "den-idle": "Idle · zsh",
                "den-web": "just",
                "den-unknown": "Unknown",
            ])
    }

    @Test func zmxClientUsesUnknownWhenProcessSnapshotFails() throws {
        let client = ZmxClient(
            executablePath: "/opt/homebrew/bin/zmx",
            commandRunner: StubTerminalCommandRunner(
                responses: [
                    ["list"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "name=den\tpid=100\n"),
                    ["-axo", "pid=,ppid=,pgid=,tpgid=,command="]: TerminalCommandResult(
                        terminationStatus: 1,
                        standardOutput: ""),
                ]))

        let snapshot = try #require(client.sessionSnapshot())
        #expect(snapshot.processNames == ["den": "Unknown"])
    }

    @Test func zmxClientKillsSessionsWithForce() {
        let client = ZmxClient(
            executablePath: "/opt/homebrew/bin/zmx",
            commandRunner: StubTerminalCommandRunner(
                responses: [
                    ["kill", "den-vi", "--force"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "")
                ]))

        #expect(client.killSession(" den-vi "))
        #expect(!client.killSession(""))
    }

    @Test func zmxSessionNameGeneratorUsesRootAndSkipsCollisions() {
        let occupied: Set<String> = ["den", "den-vi", "den-vi-2", "den-2"]

        #expect(ZmxSessionNameGenerator.normalizedSuffix(" vi/nvim!? ") == "vinvim")
        #expect(
            ZmxSessionNameGenerator.nextName(
                rootSessionName: "den",
                suffix: "vi",
                occupiedNames: occupied)
                == "den-vi-3")
        #expect(
            ZmxSessionNameGenerator.nextName(
                rootSessionName: "den",
                suffix: "",
                occupiedNames: occupied)
                == "den-3")
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

private struct StubTerminalCommandRunner: TerminalCommandRunning, Sendable {
    let responses: [[String]: TerminalCommandResult]

    func run(executablePath: String, arguments: [String]) -> TerminalCommandResult? {
        responses[arguments]
    }
}
