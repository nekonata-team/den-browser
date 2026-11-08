import DenApplication
import DenDomain
import Foundation
import Testing

@MainActor
struct BoardInputResolverTests {
    @Test func resolvesZellijCommands() {
        #expect(BoardInputResolver.resolveZellijInput(":zellij") == .welcome)
        #expect(BoardInputResolver.resolveZellijInput(":zellij   ") == .welcome)
        #expect(BoardInputResolver.resolveZellijInput(":zellij dev") == .session("dev"))
        #expect(BoardInputResolver.resolveZellijInput("other") == nil)
        #expect(BoardInputResolver.resolveZellijInput(":zellijly") == nil)
    }

    @Test func resolvesZmxCommands() {
        #expect(BoardInputResolver.resolveZmxInput(":zmx") == .missingSessionName)
        #expect(BoardInputResolver.resolveZmxInput(":zmx   ") == .missingSessionName)
        #expect(BoardInputResolver.resolveZmxInput(":zmx work") == .session("work"))
        #expect(BoardInputResolver.resolveZmxInput("other") == nil)
        #expect(BoardInputResolver.resolveZmxInput(":zmxly") == nil)
    }

    @Test func sessionNamesUseOneQuotedArgument() {
        #expect(BoardInputResolver.resolveZellijInput(":zellij 'my project'") == .session("my project"))
        #expect(BoardInputResolver.resolveZmxInput(":zmx my\\ project") == .session("my project"))
        #expect(BoardInputResolver.resolveZellijInput(":zellij my project") == .invalid)
        #expect(BoardInputResolver.resolveZmxInput(":zmx my project") == .invalid)
        #expect(BoardInputResolver.resolveZmxInput(":zmx 'unfinished") == .invalid)
        let name = "my project's session"
        #expect(
            BoardInputResolver.resolveZellijInput(RecentItem.zellij(sessionName: name).displayText) == .session(name))
        #expect(BoardInputResolver.resolveZmxInput(RecentItem.zmx(sessionName: name).displayText) == .session(name))
    }

    @Test func resolvesTerminalCommands() throws {
        let temp = FileManager.default.temporaryDirectory

        #expect(
            try BoardInputResolver.resolveTerminalInput(
                ":terminal", homeDirectory: temp, directoryExists: { $0 == temp.standardizedFileURL.path })?.get()
                == temp.standardizedFileURL.path)
        #expect(
            try BoardInputResolver.resolveTerminalInput(
                ":terminal .", homeDirectory: temp, directoryExists: { $0 == temp.standardizedFileURL.path })?.get()
                == temp.standardizedFileURL.path)
        #expect(
            try BoardInputResolver.resolveTerminalInput(
                ":terminal \(temp.path)", homeDirectory: URL(fileURLWithPath: "/"),
                directoryExists: { $0 == temp.standardizedFileURL.path })?.get()
                == temp.standardizedFileURL.path)
        #expect(
            BoardInputResolver.resolveTerminalInput(
                ":terminalnot", homeDirectory: temp, directoryExists: { $0 == temp.standardizedFileURL.path }) == nil)
    }

    @Test func rejectsMissingTerminalDirectory() {
        // Arrange
        let home = URL(fileURLWithPath: "/work")

        // Act
        let resolved = BoardInputResolver.resolveTerminalInput(
            ":terminal missing", homeDirectory: home, directoryExists: { _ in false })

        // Assert
        #expect(throws: TerminalInputError.self) { try resolved?.get() }
    }

    @Test func terminalCommandAndQuotedPath() throws {
        let input = try #require(BoardInputResolver.terminalArguments(":terminal '~/My Projects' nvim 'a b'"))
        let arguments = try input.get()
        #expect(arguments.path == "~/My Projects")
        #expect(arguments.command == "nvim 'a b'")
        #expect(throws: TerminalInputError.self) {
            try BoardInputResolver.terminalArguments(":terminal 'unfinished")?.get()
        }
        let recent = RecentItem.terminal(workingDirectory: "/tmp/a b's")
        let restored = try #require(BoardInputResolver.terminalArguments(recent.displayText)).get()
        #expect(restored.path == "/tmp/a b's")
        #expect(restored.command == nil)
    }

    @Test func resolvesURLsAndSearch() {
        let http = BoardInputResolver.resolveOpenBoardInput("https://example.com", searchEngine: .google)
        #expect(http?.url.absoluteString == "https://example.com")

        let normalized = BoardInputResolver.normalizedURL(from: "https://example.com", searchEngine: .google)
        #expect(normalized?.absoluteString == "https://example.com/")

        let domain = BoardInputResolver.resolveOpenBoardInput("example.com", searchEngine: .google)
        #expect(domain?.url.absoluteString == "https://example.com")

        let search = BoardInputResolver.resolveOpenBoardInput("hello world", searchEngine: .google)
        #expect(search?.url.absoluteString == "https://www.google.com/search?q=hello%20world")
    }

    @Test func resolvesLocalFilesAndRejectsExplicitUnsupportedSchemes() {
        let fileInput = "file://localhost/tmp/Den%20Browser/index.html"
        #expect(
            BoardInputResolver.normalizedURL(from: fileInput, searchEngine: .google)
                == URL(string: "file:///tmp/Den%20Browser/index.html"))
        #expect(BoardInputResolver.resolveOpenBoardInput("ftp://example.com", searchEngine: .google) == nil)
        #expect(BoardInputResolver.resolveOpenBoardInput("mailto:user@example.com", searchEngine: .google) == nil)
        #expect(BoardInputResolver.resolveOpenBoardInput("https://", searchEngine: .google) == nil)
    }

    @Test(arguments: ["/tmp/index.html", "/tmp/Den Browser/report #1%.html", "~/Documents/index.html"])
    func resolvesFilePathsAsLocalURLs(input: String) throws {
        // Arrange
        let expected = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)

        // Act
        let resolved = try #require(BoardInputResolver.resolveOpenBoardInput(input, searchEngine: .google))
        let normalized = BoardInputResolver.normalizedURL(from: input, searchEngine: .google)

        // Assert
        #expect(resolved.url.isFileURL)
        #expect(resolved.url == expected)
        #expect(resolved.item == .url(expected))
        #expect(normalized == expected)
        #expect(resolved.url.query == nil)
        #expect(resolved.url.fragment == nil)
    }

    @Test func stripsNewlinesWithoutChangingOtherCharacters() {
        #expect(
            WebURLPolicy.stripNewlines("https://example.com/long-\npath/to/\r\npage")
                == "https://example.com/long-path/to/page")
        #expect(
            WebURLPolicy.stripNewlines("  search query  ")
                == "  search query  ")
        #expect(WebURLPolicy.stripNewlines("single line text") == "single line text")
    }
}
