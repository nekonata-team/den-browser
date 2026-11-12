import DenIPCProtocol
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct SheetReadingTests {
    @Test(arguments: [String?.none, "#host"])
    func openShadowContentKeepsStructureAndNestedRootsWithoutChangingThePage(scope: String?) async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <div id="host"></div><script>
                const shadow = document.querySelector('#host').attachShadow({mode: 'open'});
                shadow.innerHTML = '<h2>Shadow heading</h2><a href="/next">Shadow link</a>'
                    + '<div id="nested"></div><pre><code class="language-js">  const x = 1;\\n  use(x);</code></pre>';
                shadow.querySelector('#nested').attachShadow({mode: 'open'}).innerHTML = '<p>Nested marker</p>';
                </script>
                """
        )
        let inspect = """
            JSON.stringify([document.documentElement.outerHTML,
              document.querySelector('#host').shadowRoot.innerHTML,
              document.querySelector('#host').shadowRoot.querySelector('#nested').shadowRoot.innerHTML])
            """
        let before = try await webView.evaluateJavaScript(inspect) as? String

        // Act
        let result = try await SheetReading.read(in: webView, within: scope)
        let text = try await SheetReading.text(in: webView)
        let after = try await webView.evaluateJavaScript(inspect) as? String

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        #expect(markdown.contains("## Shadow heading"))
        #expect(markdown.contains("[Shadow link](https://example.com/next)"))
        #expect(markdown.contains("Nested marker"))
        #expect(markdown.contains("```js\n  const x = 1;\n  use(x);\n```"))
        #expect(text.contains("Shadow heading\nShadow link"))
        #expect(text.contains("Nested marker"))
        #expect(text.contains("  const x = 1;\n  use(x);"))
        #expect(before == after)
    }

    @Test func slotsUseRenderedOrderAndFallbackWithoutDuplicatingLightContent() async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <div id="host"><span slot="last">Last marker</span><span slot="first">First marker</span>
                <span id="unassigned">Unassigned marker</span></div><script>
                const shadow = document.querySelector('#host').attachShadow({mode: 'open'});
                shadow.innerHTML = '<p><slot name="first">Replaced fallback</slot></p>'
                    + '<p><slot name="empty">Fallback marker</slot></p><p><slot name="last"></slot></p>';
                </script>
                """
        )

        // Act
        let result = try await SheetReading.read(in: webView)
        let text = try await SheetReading.text(in: webView)
        let unassigned = try await SheetReading.read(in: webView, within: "#unassigned")

        // Assert
        guard case .reading(_, _, let markdown) = result,
            case .reading(_, _, let unassignedMarkdown) = unassigned
        else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        for content in [markdown, text] {
            #expect(content.components(separatedBy: "First marker").count == 2)
            #expect(content.components(separatedBy: "Last marker").count == 2)
            let first = try #require(content.range(of: "First marker"))
            let fallback = try #require(content.range(of: "Fallback marker"))
            let last = try #require(content.range(of: "Last marker"))
            #expect(first.lowerBound < fallback.lowerBound)
            #expect(fallback.lowerBound < last.lowerBound)
            #expect(!content.contains("Unassigned marker"))
            #expect(!content.contains("Replaced fallback"))
        }
        #expect(unassignedMarkdown.isEmpty)
    }

    @Test func shadowStylesAndHiddenSlotsExcludeContentButKeepVisibleDescendants() async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <div id="host"><span slot="hidden">Hidden assignment</span></div>
                <div id="hidden" hidden></div><div id="closed"></div><script>
                const shadow = document.querySelector('#host').attachShadow({mode: 'open'});
                shadow.innerHTML = '<style>.hidden {display:none}</style><p class="hidden">Hidden marker</p>'
                    + '<slot name="hidden" style="display:none"></slot><slot name="missing" hidden>Hidden fallback</slot>'
                    + '<p style="visibility:hidden">Invisible marker<span style="visibility:visible">Visible marker</span></p>'
                    + '<div style="content-visibility:hidden">Skipped marker</div>'
                    + '<details><summary>Summary marker</summary>Closed details marker</details>';
                document.querySelector('#hidden').attachShadow({mode: 'open'}).innerHTML = '<p>Hidden host marker</p>';
                document.querySelector('#closed').attachShadow({mode: 'closed'}).innerHTML = '<p>Closed root marker</p>';
                </script>
                """
        )

        // Act
        let result = try await SheetReading.read(in: webView)
        let text = try await SheetReading.text(in: webView)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected Markdown reading payload")
            return
        }
        for content in [markdown, text] {
            #expect(content.contains("Visible marker"))
            #expect(content.contains("Summary marker"))
            for hidden in [
                "Hidden marker", "Hidden assignment", "Hidden fallback", "Invisible marker",
                "Skipped marker", "Closed details marker", "Hidden host marker", "Closed root marker",
            ] {
                #expect(!content.contains(hidden))
            }
        }
    }

    @Test func textWithoutShadowContentKeepsNativeFormatting() async throws {
        // Arrange
        let webView = await makeWebView(
            html: "<h1>Heading</h1><p>First<br>Second</p><pre>  code\n    indented</pre><p hidden>Hidden</p>"
        )
        let expected = try await webView.evaluateJavaScript("document.body.innerText") as? String

        // Act
        let text = try await SheetReading.text(in: webView)

        // Assert
        #expect(text == expected)
    }

    @Test func highlightedSpansInPreKeepCodeBoundariesAndWhitespace() async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <div class="highlight"><pre><span></span><span class="gp">&gt;&gt;&gt; </span><span>some_value = 1</span>
                    print(some_value)
                </pre></div>
                """
        )

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
                """
        )

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
                """
        )

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
            html: "<div class=\"highlight \(highlightClass)\">\n<pre>\(code)</pre></div>"
        )

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
                """
        )

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
                """
        )

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
                        this.attachShadow({mode: 'open'}).innerHTML = '<slot></slot><p>Shadow content marker</p>';
                        window.constructorCalls++;
                        document.getElementById('state').textContent = 'Changed by constructor';
                    }
                });
                window.constructorCalls = 0;
                document.getElementById('state').textContent = 'Unchanged marker';
                </script>
                """
        )
        let before = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String

        // Act
        let result = try await SheetReading.read(in: webView)
        _ = try await SheetReading.read(in: webView)
        let text = try await SheetReading.text(in: webView)
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
        #expect(markdown.contains("Shadow content marker"))
        #expect(markdown.contains("Unchanged marker"))
        #expect(text.contains("Custom element content"))
        #expect(text.contains("Shadow content marker"))
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
                """
        )

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
                """
        )

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
                """
        )

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
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )
        let within: String
        if scope == "ref" {
            let elements = try await SheetInteraction.query(
                selector: "main",
                visibleOnly: false,
                all: false,
                fields: [],
                in: webView
            )
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
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

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
            baseURL: URL(string: "https://example.com/source")!,
            in: webView
        )
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

    @Test func bundledGFMReadingWorksWithoutNetworkAccess() async throws {
        // Arrange
        let webView = await makeWebView(
            html: """
                <meta http-equiv="Content-Security-Policy" content="default-src 'none'">
                <h1>Offline</h1><p><del>Removed</del></p>
                <ul><li><input type="checkbox" checked>Done</li></ul>
                <table><tr><th>Name</th></tr><tr><td>Value</td></tr></table>
                """
        )
        _ = try await webView.evaluateJavaScript(
            """
            globalThis.__denNetworkAttempts = 0;
            for (const name of ['fetch', 'XMLHttpRequest', 'WebSocket', 'EventSource']) {
                globalThis[name] = function () {
                    globalThis.__denNetworkAttempts++;
                    throw new Error('Network access forbidden');
                };
            }
            null;
            """,
            in: nil,
            contentWorld: SheetDOMRuntime.contentWorld
        )

        // Act
        let result = try await SheetReading.read(in: webView)

        // Assert
        guard case .reading(_, _, let markdown) = result else {
            Issue.record("Expected offline Markdown reading payload")
            return
        }
        #expect(markdown.contains("# Offline"))
        #expect(markdown.contains("~Removed~"))
        #expect(markdown.contains("[x] Done"))
        #expect(markdown.contains("| Name |"))
        #expect(markdown.contains("| Value |"))
        let attempts =
            try await webView.evaluateJavaScript(
                "globalThis.__denNetworkAttempts",
                in: nil,
                contentWorld: SheetDOMRuntime.contentWorld
            ) as? Int
        #expect(attempts == 0)
    }

    @Test func documentWithoutHTMLBodyReportsUnsupportedReading() async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            "<response>XML result</response>",
            mimeType: "application/xml",
            baseURL: URL(string: "https://example.com/result.xml")!,
            in: webView
        )

        // Act / Assert
        await #expect(throws: (any Error).self) {
            _ = try await SheetReading.read(in: webView)
        }
        #expect(try await SheetReading.text(in: webView) == "XML result")
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
