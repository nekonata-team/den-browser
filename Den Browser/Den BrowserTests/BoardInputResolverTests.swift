import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct BoardInputResolverTests {
    @Test func resolvesZellijCommands() {
        #expect(BoardInputResolver.resolveZellijInput(":zellij") == .welcome)
        #expect(BoardInputResolver.resolveZellijInput(":zellij   ") == .welcome)
        #expect(BoardInputResolver.resolveZellijInput(":zellij dev") == .session("dev"))
        #expect(BoardInputResolver.resolveZellijInput("other") == nil)
    }

    @Test func resolvesZmxCommands() {
        #expect(BoardInputResolver.resolveZmxInput(":zmx") == .missingSessionName)
        #expect(BoardInputResolver.resolveZmxInput(":zmx   ") == .missingSessionName)
        #expect(BoardInputResolver.resolveZmxInput(":zmx work") == .session("work"))
        #expect(BoardInputResolver.resolveZmxInput("other") == nil)
    }

    @Test func resolvesTerminalCommands() throws {
        let temp = FileManager.default.temporaryDirectory

        #expect(
            try BoardInputResolver.resolveTerminalInput(":terminal", homeDirectory: temp)?.get()
                == temp.standardizedFileURL.path)
        #expect(
            try BoardInputResolver.resolveTerminalInput(":terminal .", homeDirectory: temp)?.get()
                == temp.standardizedFileURL.path)
        #expect(
            BoardInputResolver.resolveTerminalInput(":terminalnot", homeDirectory: temp) == nil)
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

    @Test func stripsNewlinesWithoutChangingOtherCharacters() {
        #expect(
            SheetURLPolicy.stripNewlines("https://example.com/long-\npath/to/\r\npage")
                == "https://example.com/long-path/to/page")
        #expect(
            SheetURLPolicy.stripNewlines("  search query  ")
                == "  search query  ")
        #expect(SheetURLPolicy.stripNewlines("single line text") == "single line text")
    }
}
