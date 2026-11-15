import AppKit
import DenIPCProtocol
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct SheetSnapshotQueryTests {
    @Test func semanticNamesUseCaptionsRatherThanFormValues() async throws {
        // Arrange
        let webView = makeSheetInteractionWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <button value="save" onclick="this.dataset.clicked = 'yes'">Save changes</button>
            <input type="submit" value="Send">
            <input type="password" value="secret">
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        let elements = try await SheetInteraction.query(
            selector: "button, input",
            visibleOnly: true,
            all: true,
            fields: ["name"],
            in: webView
        )
        try await SheetInteraction.click(role: "button", name: "Save changes", exact: true, in: webView)
        let clicked = try await SheetInteraction.attribute(target: "button", name: "data-clicked", in: webView)

        // Assert
        #expect(elements.map(\.name) == ["Save changes", "Send", ""])
        #expect(clicked == "yes")
    }

    @Test(arguments: [
        ("<button disabled aria-disabled='false'>Save</button>", false),
        ("<fieldset disabled><button>Save</button></fieldset>", false),
        ("<fieldset disabled><legend><button>Save</button></legend></fieldset>", true),
    ])
    func enabledStateRespectsNativeDisabling(html: String, enabled: Bool) async throws {
        // Arrange
        let webView = makeSheetInteractionWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(html, baseURL: URL(string: "https://example.com/")!, in: webView)

        // Act
        let actual = try await SheetInteraction.isEnabled(target: "button", in: webView)

        // Assert
        #expect(actual == enabled)
    }

    @Test func queryAndScopedSnapshotReturnVisibleElementsAndRequestedAttributes() async throws {
        // Arrange
        let webView = makeSheetInteractionWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <html>
            <body>
              <h1>Inbox</h1>
              <div id="dialog" role="dialog">
                <button id="github" role="option" aria-label="GitHub" class="choice" data-email="github@example.com">GitHub</button>
                <button id="hidden" style="display:none">Hidden</button>
              </div>
              <button id="outside">Outside</button>
            </body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        let elements = try await SheetInteraction.query(
            selector: "button",
            visibleOnly: true,
            all: true,
            fields: ["text", "class", "attr:data-email"],
            in: webView
        )

        // Assert
        #expect(elements.count == 2)
        let github = try #require(elements.first(where: { $0.text == "GitHub" }))
        #expect(github.visible)
        #expect(github.attributes?["class"] == "choice")
        #expect(github.attributes?["data-email"] == "github@example.com")
        #expect(github.ref.hasPrefix("@e"))

        // Act
        let fullSnapshot = try await SheetInteraction.snapshot(
            in: webView,
            interactiveOnly: false
        )

        // Assert
        #expect(fullSnapshot.contains("Inbox"))
        #expect(fullSnapshot.contains("[heading:level=1]"))

        // Act
        let snapshot = try await SheetInteraction.snapshot(
            in: webView,
            interactiveOnly: true,
            within: "#dialog"
        )

        // Assert
        #expect(snapshot.contains("GitHub"))
        #expect(!snapshot.contains("Outside"))
        #expect(!snapshot.contains("Hidden"))
    }

    @Test func interactiveSnapshotFormatsLabelsContainersContextAndRedactsPasswords() async throws {
        // Arrange
        let webView = makeSheetInteractionWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <button id="save"></button>
            <label for="save">Save changes</label>
            <div role="menu">
              <span>Available actions</span>
              <button role="menuitem">Save</button>
              <button>Continue</button>
              <span role="status">Updated</span>
            </div>
            <input type="search" value="current">
            <input type="text" value="">
            <input type="password" value="secret">
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        let snapshot = try await SheetInteraction.snapshot(in: webView, interactiveOnly: true)
        let lines = snapshot.split(separator: "\n").map(String.init)
        let contextLine = try #require(lines.first { $0.contains("Available actions") })
        let menuIndex = try #require(lines.firstIndex { $0.contains("[menu]") })
        let buttonIndex = try #require(lines.firstIndex { $0.contains("[button]") && $0.contains("Continue") })
        let menuIndent = lines[menuIndex].prefix(while: { $0 == " " }).count
        let buttonIndent = lines[buttonIndex].prefix(while: { $0 == " " }).count

        // Assert
        #expect(snapshot.contains("Save changes"))
        #expect(contextLine.contains("text \""))
        #expect(contextLine.contains("Available actions"))
        #expect(!contextLine.contains("Save"))
        #expect(!contextLine.contains("Continue"))
        #expect(!contextLine.contains("Updated"))
        #expect(menuIndex < buttonIndex)
        #expect(buttonIndent > menuIndent)
        #expect(snapshot.contains("[value=\"current\"]"))
        #expect(snapshot.contains("[value=\"\"]"))
        #expect(!snapshot.contains("secret"))
    }

    @Test func refTargetsUseWeakReferencesAndFollowClonedElements() async throws {
        // Arrange
        let webView = makeSheetInteractionWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <button id="target" onclick="this.dataset.clicked = 'yes'">Target</button>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )
        let element = try #require(
            await SheetInteraction.query(
                selector: "#target",
                visibleOnly: true,
                all: false,
                fields: ["text"],
                in: webView
            ).first
        )
        let usesWeakReference =
            try await webView.callAsyncJavaScript(
                "return typeof window.__denRefs.get(ref)?.deref === 'function';",
                arguments: ["ref": element.ref],
                in: nil,
                contentWorld: SheetDOMRuntime.contentWorld
            ) as? Bool

        // Act
        _ = try await webView.evaluateJavaScript(
            """
            const target = document.getElementById('target');
            target.replaceWith(target.cloneNode(true));
            """
        )
        try await SheetInteraction.click(target: element.ref, in: webView)
        let clicked =
            try await webView.evaluateJavaScript(
                "document.getElementById('target').dataset.clicked"
            ) as? String

        // Assert
        #expect(usesWeakReference == true)
        #expect(clicked == "yes")
    }

    @Test func snapshotStatesAndPointReadsUseTheCurrentElementState() async throws {
        // Arrange
        let webView = makeSheetInteractionWebView()
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <input id="check" type="checkbox" checked aria-label="Notifications">
            <button id="disabled" disabled>Save</button>
            <button id="hidden" style="display:none">Hidden</button>
            <div id="box" style="position: absolute; left: 50px; top: 100px; width: 200px; height: 80px;"></div>
            """,
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        // Act
        let snapshot = try await SheetInteraction.snapshot(
            in: webView,
            interactiveOnly: true
        )
        let text = try await SheetInteraction.text(target: "#disabled", in: webView)
        let attribute = try await SheetInteraction.attribute(
            target: "#disabled",
            name: "id",
            in: webView
        )
        let count = try await SheetInteraction.count(selector: "button", in: webView)
        let visible = try await SheetInteraction.isVisible(target: "#hidden", in: webView)
        let enabled = try await SheetInteraction.isEnabled(target: "#disabled", in: webView)
        let checked = try await SheetInteraction.isChecked(target: "#check", in: webView)
        let rect = try await SheetInteraction.box(target: "#box", in: webView)

        // Assert
        #expect(snapshot.contains("[checked]"))
        #expect(snapshot.contains("[disabled]"))
        #expect(!snapshot.contains("Hidden"))
        #expect(text == "Save")
        #expect(attribute == "disabled")
        #expect(count == 2)
        #expect(!visible)
        #expect(!enabled)
        #expect(checked)
        #expect(rect.origin.x == 50)
        #expect(rect.origin.y == 100)
        #expect(rect.size.width == 200)
        #expect(rect.size.height == 80)
    }
}
