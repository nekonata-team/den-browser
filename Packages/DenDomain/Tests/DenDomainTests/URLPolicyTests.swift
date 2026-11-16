import DenDomain
import Foundation
import Testing

nonisolated struct URLPolicyTests {
    @Test func webURLPolicyAcceptsWebAndLocalFilesAndRejectsUnsupported() throws {
        // Arrange
        let supported = [
            "http://example.com/",
            "https://example.com/path",
            "HTTP://EXAMPLE.COM/",
            "file:///tmp/example.html",
            "file://localhost/tmp/example.html",
        ]
        let unsupported = [
            "https://",
            "http:///path",
            "ftp://example.com/",
            "ftp://localhost/path",
            "file:relative.html",
            "file://localhost",
            "file://server/share/example.html",
            "data:text/plain,example",
            "about:blank",
            "mailto:user@example.com",
            "example.com/no-scheme",
        ]

        // Act / Assert
        for value in supported {
            let url = try #require(URL(string: value))
            #expect(WebURLPolicy.isSupported(url))
        }
        for value in unsupported {
            let url = try #require(URL(string: value))
            #expect(!WebURLPolicy.isSupported(url))
        }
    }

    @Test func webURLPolicyNormalizesSchemeHostRootPathAndFileLocalhost() throws {
        // Arrange
        let upperHTTP = try #require(URL(string: "HTTP://EXAMPLE.TEST"))
        let withPath = try #require(URL(string: "HTTPS://EXAMPLE.TEST/App"))
        let fileLocalhost = try #require(URL(string: "file://localhost/tmp/a%20b.html?mode=test#section"))
        let fileRemote = try #require(URL(string: "file://server/share/a.html"))

        // Act / Assert
        #expect(WebURLPolicy.canonicalSheetURL(upperHTTP) == URL(string: "http://example.test/"))
        #expect(WebURLPolicy.canonicalSheetURL(withPath) == URL(string: "https://example.test/App"))
        #expect(
            WebURLPolicy.canonicalSheetURL(fileLocalhost) == URL(string: "file:///tmp/a%20b.html?mode=test#section")
        )
        #expect(WebURLPolicy.canonicalSheetURL(fileRemote) == fileRemote)
    }

    @Test func webURLPolicyStripsNewlinesAndJoinsPastedLines() {
        // Arrange / Act / Assert
        #expect(
            WebURLPolicy.normalizePastedText("  first\nsecond\r\nthird  ", joiningLineBreaksWith: "")
                == "firstsecondthird"
        )
        #expect(WebURLPolicy.normalizePastedText("  first\nsecond  ", joiningLineBreaksWith: " ") == "first second")
        #expect(WebURLPolicy.stripNewlines("single-line") == "single-line")
        #expect(WebURLPolicy.stripNewlines("line1\nline2\r\nline3") == "line1line2line3")
    }

    @Test func externalURLPolicyRejectsWebKitAndSchemelessURLs() throws {
        // Arrange
        let supported = [
            try #require(URL(string: "testapp://open/example")),
            try #require(URL(string: "mailto:user@example.com")),
        ]
        let rejected = [
            try #require(URL(string: "https://example.com/")),
            try #require(URL(string: "HTTP://example.com/")),
            try #require(URL(string: "file:///tmp/example.html")),
            try #require(URL(string: "about:blank")),
            try #require(URL(string: "javascript:void(0)")),
            try #require(URL(string: "/relative/only")),
        ]

        // Act / Assert
        #expect(supported.allSatisfy(ExternalURLPolicy.isSupported))
        #expect(rejected.allSatisfy { !ExternalURLPolicy.isSupported($0) })
    }

    @Test func denAPIPolicyAcceptsOnlyLocalHTMLFiles() throws {
        // Arrange
        let accepted = [
            try #require(URL(string: "file:///tmp/sketch.html")),
            try #require(URL(string: "file:///tmp/sketch.htm")),
            try #require(URL(string: "file://localhost/tmp/INDEX.HTML")),
        ]
        let rejectedNonNil = [
            try #require(URL(string: "https://example.com/index.html")),
            try #require(URL(string: "file:///tmp/report.pdf")),
            try #require(URL(string: "file://remote/tmp/index.html")),
        ]

        // Act / Assert
        #expect(accepted.allSatisfy { DenAPIPolicy.isLocalHTML($0) })
        #expect(!DenAPIPolicy.isLocalHTML(nil))
        #expect(rejectedNonNil.allSatisfy { !DenAPIPolicy.isLocalHTML($0) })
    }
}
