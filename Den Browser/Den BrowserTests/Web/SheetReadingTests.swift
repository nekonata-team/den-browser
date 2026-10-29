import DenIPCProtocol
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct SheetReadingTests {
    @Test func highlightedSpansInPreKeepCodeBoundariesAndWhitespace() async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <div class="highlight"><pre><span></span><span class="gp">&gt;&gt;&gt; </span><span>some_value = 1</span>
                    print(some_value)
                </pre></div>
                """)

        // Act
        let result = try await SheetReading.read(in: webView)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(markdown == "```\n>>> some_value = 1\n    print(some_value)\n```")
    }

    @Test func preWithSiblingControlsUsesOnlyTheCodeAndKeepsItsLanguage() async throws {
        // Arrange
        let content = "fn main() {\n    println!(\"hello\");\n}"
        let webView = await makeWebView(
            html: """
                <pre><div class="buttons"><button>Run control marker</button></div>
                <code class="language-rust">\(content)</code></pre>
                """)

        // Act
        let result = try await SheetReading.read(in: webView)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(markdown == "```rust\n\(content)\n```")
    }

    @Test func tableCellLineBreaksStayWithinTheSameRow() async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <table><tr><th>Name</th><th>Value</th></tr>
                <tr><td>Example</td><td>First<br>Second</td></tr>
                <tr><td>Paragraphs</td><td><p>Third</p><p>Fourth</p></td></tr></table>
                """)

        // Act
        let result = try await SheetReading.read(in: webView)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(markdown.contains("| Example | First<br>Second |"))
        #expect(markdown.contains("| Paragraphs | Third<br><br>Fourth |"))
        #expect(markdown.split(separator: "\n").count == 4)
    }

    @Test(arguments: ["highlight-source-md", "highlight-text-md"], [false, true])
    func highlightedCodeUsesAFenceLongerThanItsContent(highlightClass: String, wrapped: Bool) async throws {
        // Arrange
        let content = "```js\nconsole.log(1)\n```"
        let code = wrapped ? "<code>\(content)</code>" : content
        let webView = await makeWebView(
            html: "<div class=\"highlight \(highlightClass)\">\n<pre>\(code)</pre></div>")

        // Act
        let result = try await SheetReading.read(in: webView)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(markdown == "````md\n\(content)\n````")
    }

    @Test(arguments: [String?.none, "#closed", "#summary", "#summary-child", "#inside", "#inside-child"])
    func closedDetailsKeepsOnlyItsSummaryIncludingScopedReads(scope: String?) async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <details id="closed">Hidden direct marker
                <summary id="summary">Summary marker<span id="summary-child">Summary child marker</span></summary>
                <p id="inside">Closed content marker<span id="inside-child">Closed child marker</span></p>
                </details>
                <details open><summary>Open summary</summary><p>Open content marker</p></details>
                """)

        // Act
        let result = try await SheetReading.read(in: webView, within: scope)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        if scope == "#inside" || scope == "#inside-child" {
            #expect(markdown.isEmpty)
        } else {
            #expect(markdown.contains("Summary child marker"))
            if scope != "#summary-child" { #expect(markdown.contains("Summary marker")) }
        }
        #expect(!markdown.contains("Hidden direct marker"))
        #expect(!markdown.contains("Closed content marker"))
        #expect(!markdown.contains("Closed child marker"))
        #expect(markdown.contains("Open content marker") == (scope == nil))
    }

    @Test(arguments: [String?.none, "#hidden", "#hidden-child"])
    func contentVisibilityHiddenExcludesTheWholeSubtree(scope: String?) async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <section id="hidden" style="content-visibility:hidden">
                <p id="hidden-child">Hidden content marker</p></section><p>Visible marker</p>
                """)

        // Act
        let result = try await SheetReading.read(in: webView, within: scope)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(markdown == (scope == nil ? "Visible marker" : ""))
    }

    @Test func readingDoesNotRunCustomElementConstructors() async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <p id="state">Unchanged marker</p><read-probe>Custom element content</read-probe>
                <script>
                window.constructorCalls = 0;
                customElements.define('read-probe', class extends HTMLElement {
                    constructor() {
                        super();
                        window.constructorCalls++;
                        document.getElementById('state').textContent = 'Changed by constructor';
                    }
                });
                window.constructorCalls = 0;
                document.getElementById('state').textContent = 'Unchanged marker';
                </script>
                """)
        let before = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String

        // Act
        let result = try await SheetReading.read(in: webView)
        _ = try await SheetReading.read(in: webView)
        let constructorCalls = try await webView.evaluateJavaScript("window.constructorCalls") as? Int
        let after = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String

        // Assert
        #expect(constructorCalls == 0)
        #expect(before == after)
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(markdown.contains("Custom element content"))
        #expect(markdown.contains("Unchanged marker"))
    }

    @Test(arguments: [String?.none, "#scope", "#child"])
    func readingKeepsVisibleDescendantsOfHiddenElements(scope: String?) async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <section id="scope" style="visibility:hidden">
                Hidden text marker <img src="data:," alt="Hidden image marker">
                <span id="child" style="visibility:visible">Visible child marker</span>
                </section>
                """)

        // Act
        let result = try await SheetReading.read(in: webView, within: scope)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(markdown.contains("Visible child marker"))
        #expect(!markdown.contains("Hidden text marker"))
        #expect(!markdown.contains("Hidden image marker"))
    }

    @Test func emptyTablesDoNotPreventReadingAndKeepTheirCaptions() async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <p>Before marker</p><table></table>
                <table><tr hidden><td>Hidden row marker</td></tr></table>
                <table><caption>Caption marker</caption></table><p>After marker</p>
                """)

        // Act
        let result = try await SheetReading.read(in: webView)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(markdown.contains("Before marker"))
        #expect(markdown.contains("After marker"))
        #expect(markdown.contains("Caption marker"))
        #expect(!markdown.contains("Hidden row marker"))
    }

    @Test func tableCellPipesAreEscapedIncludingHeadersAndInlineCode() async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <table><tr><th>Expression | sample</th><th>Code</th></tr>
                <tr><td>a | b</td><td><code>a | b</code></td></tr></table>
                """)

        // Act
        let result = try await SheetReading.read(in: webView)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(markdown.contains("| Expression \\| sample | Code |"))
        #expect(markdown.contains("| a \\| b | `a \\| b` |"))
    }

    @Test(arguments: ["main", "#heading", "ref", "#concealed"])
    func readingWithinSelectsOneElementAndPreservesItsStructure(scope: String) async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        SheetDOMRuntime.install(on: configuration.userContentController)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <title>Scoped reading</title><nav>Navigation marker</nav>
            <main><h2 id="heading">Focus</h2><p>Body content</p></main>
            <div style="display:none"><article id="concealed">Concealed content</article></div>
            <footer>Footer marker</footer>
            """, baseURL: URL(string: "https://example.com/")!, in: webView)
        let within: String
        if scope == "ref" {
            let elements = try await SheetInteraction.query(
                selector: "main", visibleOnly: false, all: false, fields: [], in: webView)
            within = try #require(elements.first).ref
        } else {
            within = scope
        }

        // Act
        let result = try await SheetReading.read(in: webView, within: within)

        // Assert
        guard case .reading(let title, _, let markdown) = result else {
            Issue.record("Expected scoped Markdown reading payload")
            return
        }
        #expect(title == "Scoped reading")
        if scope == "#concealed" {
            #expect(markdown.isEmpty)
        } else {
            #expect(markdown.contains("## Focus"))
            #expect(!markdown.contains("Navigation marker"))
            #expect(!markdown.contains("Footer marker"))
            #expect(markdown.contains("Body content") == (scope != "#heading"))
        }
    }

    @Test(arguments: ["#missing", "main, footer", "[", "@e99999", ""])
    func invalidScopeFailsInsteadOfReadingTheWholePage(scope: String) async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        SheetDOMRuntime.install(on: configuration.userContentController)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            "<main>Body</main><footer>Footer</footer>",
            baseURL: URL(string: "https://example.com/")!, in: webView)

        // Act / Assert
        do {
            _ = try await SheetReading.read(in: webView, within: scope)
            Issue.record("Expected an invalid scope to fail")
        } catch {
            if scope == "#missing" {
                #expect(error.localizedDescription.contains("Scope not found"))
            }
        }
    }

    @Test func readingPreservesStructureAndLeavesLiveDOMUnchanged() async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <html><head><title>Reading fixture</title><base href="https://example.com/docs/">
            <style>.concealed { display: none; }</style></head><body>
            <nav><a href="/home">Home</a></nav>
            <h1>Guide</h1><h2>Steps</h2><ul><li>First</li><li>Second</li></ul>
            <p><a href="next">Next page</a><img src="diagram.png" alt="Diagram"></p>
            <pre><code class="language-js">const value = 1;</code></pre>
            <table><thead><tr><th>Name</th><th>Value</th></tr></thead>
            <tbody><tr><td>Example</td><td>42</td></tr></tbody></table>
            <p hidden>Hidden marker</p><p class="concealed">CSS hidden marker</p>
            <script>window.denSheetRead = { read: () => 'Page override' };</script>
            <footer>Footer content</footer>
            </body></html>
            """,
            baseURL: URL(string: "https://example.com/source")!, in: webView)
        let before = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String

        // Act
        let result = try await SheetReading.read(in: webView)
        let repeatedResult = try await SheetReading.read(in: webView)
        let after = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String

        // Assert
        guard case .reading(let title, let url, let markdown) = result,
            case .reading(_, _, let repeatedMarkdown) = repeatedResult
        else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(title == "Reading fixture")
        #expect(url == webView.url?.absoluteString)
        #expect(markdown.contains("# Guide"))
        #expect(markdown.contains("## Steps"))
        #expect(markdown.contains("*   First"))
        #expect(markdown.contains("[Home](https://example.com/home)"))
        #expect(markdown.contains("[Next page](https://example.com/docs/next)"))
        #expect(markdown.contains("![Diagram](https://example.com/docs/diagram.png)"))
        #expect(markdown.contains("```js\nconst value = 1;\n```"))
        #expect(markdown.contains("| Name | Value |"))
        #expect(markdown.contains("| Example | 42 |"))
        #expect(markdown.contains("Footer content"))
        #expect(!markdown.contains("Hidden marker"))
        #expect(!markdown.contains("CSS hidden marker"))
        #expect(!markdown.contains("Page override"))
        #expect(before == after)
        #expect(markdown == repeatedMarkdown)
    }

    @Test func documentWithoutHTMLBodyReportsUnsupportedReading() async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            "<response>XML result</response>", mimeType: "application/xml",
            baseURL: URL(string: "https://example.com/result.xml")!, in: webView)

        // Act / Assert
        await #expect(throws: (any Error).self) {
            _ = try await SheetReading.read(in: webView)
        }
    }

    private func makeWebView(html: String) async -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(html, baseURL: URL(string: "https://example.com/")!, in: webView)
        return webView
    }
}
