import Foundation
import WebKit

enum SheetInteractionError: LocalizedError {
    case elementNotFound(String)
    case executionFailed(String)
    case timedOut(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .elementNotFound(let target):
            return "Element not found: \(target)"
        case .executionFailed(let reason):
            return reason
        case .timedOut(let target):
            return "Timed out waiting for: \(target)"
        case .invalidArgument(let message):
            return message
        }
    }
}

enum SheetWaitState: String, Sendable {
    case attached
    case visible
    case hidden
    case detached
}

enum SheetLoadState: String, Sendable {
    case domcontentloaded
    case load
    case networkidle
}

private final class SheetJavaScriptResult: @unchecked Sendable {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }
}

@MainActor
enum SheetInteraction {
    private static let interactiveSelectors = [
        "a[href]", "button", "input", "select", "textarea",
        "[role=\"button\"]", "[role=\"link\"]", "[role=\"checkbox\"]", "[role=\"menuitem\"]",
        "[role=\"tab\"]", "[role=\"switch\"]", "[tabindex]:not([tabindex=\"-1\"])",
        "summary", "[contenteditable=\"true\"]",
    ]

    private static let defaultQueryFields = ["tag", "role", "name", "text"]

    static func queryFields(from raw: String?) throws -> [String] {
        let fields =
            raw?.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? defaultQueryFields
        let allowed = Set([
            "tag", "role", "name", "text", "value", "checked",
            "disabled", "selected", "expanded", "visible", "class",
        ])

        guard !fields.isEmpty,
            fields.allSatisfy({ field in
                allowed.contains(field) || (field.hasPrefix("attr:") && field.count > 5)
            })
        else {
            throw SheetInteractionError.invalidArgument(
                "Invalid query field. Use tag, role, name, text, value, checked, disabled, selected, expanded, visible, class, or attr:<name>."
            )
        }

        return fields
    }

    static func snapshot(
        in webView: WKWebView,
        interactiveOnly: Bool,
        within: String? = nil
    ) async throws -> String {
        let withinLiteral = try javascriptLiteral(within)
        let selectorsLiteral = try javascriptLiteral(interactiveSelectors)
        let script = operationScript(
            """
            const within = \(withinLiteral);
            const selectors = \(selectorsLiteral);
            let scope = document;

            if (within !== null) {
                try {
                    if (within.startsWith('@')) {
                        scope = denResolveTarget(within);
                        if (!scope) return { ok: false, error: 'Scope not found: ' + within };
                    } else {
                        const scopes = Array.from(document.querySelectorAll(within));
                        if (scopes.length === 0) return { ok: false, error: 'Scope not found: ' + within };
                        if (scopes.length > 1) return { ok: false, error: 'Scope matched multiple elements: ' + within };
                        scope = scopes[0];
                    }
                } catch (error) {
                    return { ok: false, error: 'Invalid scope selector: ' + within };
                }
            }

            let elements = scope instanceof Element
                ? [scope, ...Array.from(scope.querySelectorAll('*'))]
                : Array.from(scope.querySelectorAll('*'));
            elements = elements
                .filter(el => denIsVisible(el) && denSnapshotEligible(el, selectors));
            if (\(interactiveOnly)) elements = elements.filter(el => el.matches(selectors.join(',')));
            const elementSet = new Set(elements);
            const lines = elements.map(el => {
                const ref = denRefFor(el);
                const role = denRole(el);
                const level = denSnapshotLevel(el);
                const name = denSnapshotName(el, role);
                const truncatedName = name.length > 80 ? name.slice(0, 77) + '...' : name;
                let depth = 0;
                let parent = el.parentElement;
                while (parent) {
                    if (elementSet.has(parent)) depth++;
                    parent = parent.parentElement;
                }
                let line = '  '.repeat(depth) + ref + ' [' + role;
                if (level !== null) line += ':level=' + level;
                line += ']';
                if (truncatedName) line += ' ' + JSON.stringify(truncatedName);
                const states = denSnapshotStates(el);
                if (states.length) line += ' [' + states.join(',') + ']';
                return line;
            });
            return { ok: true, snapshot: lines.join('\\n') };
            """
        )
        let result = try await evaluate(script, in: webView)
        let dictionary = try resultDictionary(from: result)
        return dictionary["snapshot"] as? String ?? ""
    }

    static func query(
        selector: String,
        visibleOnly: Bool,
        all: Bool,
        fields: [String],
        in webView: WKWebView
    ) async throws -> [DenSheetElementInfo] {
        let selectorLiteral = try javascriptLiteral(selector)
        let fieldsLiteral = try javascriptLiteral(fields)
        let script = operationScript(
            """
            const selector = \(selectorLiteral);
            const fields = \(fieldsLiteral);
            let elements;
            try {
                elements = Array.from(document.querySelectorAll(selector));
            } catch (error) {
                return { ok: false, error: 'Invalid selector: ' + selector };
            }
            if (\(visibleOnly)) elements = elements.filter(denIsVisible);
            if (!\(all)) elements = elements.slice(0, 1);
            return { ok: true, elements: elements.map(el => denInspect(el, fields)) };
            """
        )
        let result = try await evaluate(script, in: webView)
        let dictionary = try resultDictionary(from: result)
        guard let rawElements = dictionary["elements"] as? [Any] else {
            throw SheetInteractionError.executionFailed("Invalid query result")
        }
        return try rawElements.map(elementInfo(from:))
    }

    @discardableResult
    static func click(
        target: String? = nil,
        role: String? = nil,
        name: String? = nil,
        exact: Bool = false,
        in webView: WKWebView
    ) async throws -> CGRect {
        let hasSemanticTarget = role != nil || name != nil
        guard hasSemanticTarget ? target == nil && role != nil && name != nil : target != nil else {
            throw SheetInteractionError.invalidArgument(
                "Click requires either a selector/ref or both --role and --name.")
        }

        let targetLiteral = try javascriptLiteral(target)
        let roleLiteral = try javascriptLiteral(role)
        let nameLiteral = try javascriptLiteral(name)
        let script = operationScript(
            """
            const target = \(targetLiteral);
            const role = \(roleLiteral);
            const name = \(nameLiteral);
            let el = null;

            try {
                if (role !== null || name !== null) {
                    const normalizedRole = denNormalize(role).toLowerCase();
                    const normalizedName = denNormalize(name);
                    const candidates = Array.from(document.querySelectorAll('*'))
                        .filter(candidate => denIsVisible(candidate))
                        .filter(candidate => denRole(candidate) === normalizedRole)
                        .filter(candidate => {
                            const candidateName = denAccessibleName(candidate);
                            return \(exact)
                                ? candidateName === normalizedName
                                : candidateName.includes(normalizedName);
                        });
                    if (candidates.length === 0) {
                        return { ok: false, error: 'Element not found: role=' + role + ', name=' + name };
                    }
                    if (candidates.length > 1) {
                        return { ok: false, error: 'Multiple elements found: role=' + role + ', name=' + name };
                    }
                    el = candidates[0];
                } else {
                    el = denResolveTarget(target);
                }
            } catch (error) {
                return { ok: false, error: 'Invalid selector: ' + target };
            }

            if (!el) return { ok: false, error: 'Element not found: ' + (target || role) };
            el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
            el.focus();
            const rect = el.getBoundingClientRect();
            const clientX = rect.left + rect.width / 2;
            const clientY = rect.top + rect.height / 2;
            const pointerBase = {
                bubbles: true,
                cancelable: true,
                view: window,
                button: 0,
                buttons: 1,
                clientX: clientX,
                clientY: clientY,
                pointerId: 1,
                pointerType: 'mouse',
                isPrimary: true
            };
            el.dispatchEvent(new PointerEvent('pointerdown', pointerBase));
            el.dispatchEvent(new MouseEvent('mousedown', pointerBase));
            el.dispatchEvent(new PointerEvent('pointerup', { ...pointerBase, buttons: 0 }));
            el.dispatchEvent(new MouseEvent('mouseup', { ...pointerBase, buttons: 0 }));
            if (typeof el.click !== 'function') return { ok: false, error: 'Element is not clickable' };
            el.click();
            return { ok: true, rect: { x: rect.left, y: rect.top, width: rect.width, height: rect.height } };
            """
        )
        let result = try await evaluate(script, in: webView)
        return try extractRect(from: result, scale: webView.pageZoom * webView.magnification)
    }

    @discardableResult
    static func fill(target: String, value: String, in webView: WKWebView) async throws -> CGRect {
        let targetLiteral = try javascriptLiteral(target)
        let valueLiteral = try javascriptLiteral(value)
        let script = operationScript(
            """
            const target = \(targetLiteral);
            const value = \(valueLiteral);
            let el;
            try {
                el = denResolveTarget(target);
            } catch (error) {
                return { ok: false, error: 'Invalid selector: ' + target };
            }
            if (!el) return { ok: false, error: 'Element not found: ' + target };
            el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
            el.focus();
            const rect = el.getBoundingClientRect();
            if (!denSetValue(el, value)) {
                return { ok: false, error: 'Element does not support values: ' + target };
            }
            return { ok: true, rect: { x: rect.left, y: rect.top, width: rect.width, height: rect.height } };
            """
        )
        let result = try await evaluate(script, in: webView)
        return try extractRect(from: result, scale: webView.pageZoom * webView.magnification)
    }

    static func value(target: String, in webView: WKWebView) async throws -> String {
        let targetLiteral = try javascriptLiteral(target)
        let script = operationScript(
            """
            const target = \(targetLiteral);
            let el;
            try {
                el = denResolveTarget(target);
            } catch (error) {
                return { ok: false, error: 'Invalid selector: ' + target };
            }
            if (!el) return { ok: false, error: 'Element not found: ' + target };
            const value = denValue(el);
            if (value === null) return { ok: false, error: 'Element does not expose a value: ' + target };
            return { ok: true, value: value };
            """
        )
        let result = try await evaluate(script, in: webView)
        let dictionary = try resultDictionary(from: result)
        guard let value = dictionary["value"] as? String else {
            throw SheetInteractionError.executionFailed("Invalid value result")
        }
        return value
    }

    static func text(target: String, in webView: WKWebView) async throws -> String {
        let targetLiteral = try javascriptLiteral(target)
        let script = operationScript(
            """
            const target = \(targetLiteral);
            let el;
            try {
                el = denResolveTarget(target);
            } catch (error) {
                return { ok: false, error: 'Invalid selector: ' + target };
            }
            if (!el) return { ok: false, error: 'Element not found: ' + target };
            return { ok: true, text: denText(el) };
            """
        )
        let result = try await evaluate(script, in: webView)
        let dictionary = try resultDictionary(from: result)
        guard let text = dictionary["text"] as? String else {
            throw SheetInteractionError.executionFailed("Invalid text result")
        }
        return text
    }

    static func attribute(target: String, name: String, in webView: WKWebView) async throws -> String {
        let targetLiteral = try javascriptLiteral(target)
        let nameLiteral = try javascriptLiteral(name)
        let script = operationScript(
            """
            const target = \(targetLiteral);
            const name = \(nameLiteral);
            let el;
            try {
                el = denResolveTarget(target);
            } catch (error) {
                return { ok: false, error: 'Invalid selector: ' + target };
            }
            if (!el) return { ok: false, error: 'Element not found: ' + target };
            const value = el.getAttribute(name);
            if (value === null) return { ok: false, error: 'Attribute not found: ' + name };
            return { ok: true, attribute: value };
            """
        )
        let result = try await evaluate(script, in: webView)
        let dictionary = try resultDictionary(from: result)
        guard let value = dictionary["attribute"] as? String else {
            throw SheetInteractionError.executionFailed("Invalid attribute result")
        }
        return value
    }

    static func count(selector: String, in webView: WKWebView) async throws -> Int {
        let selectorLiteral = try javascriptLiteral(selector)
        let script = operationScript(
            """
            const selector = \(selectorLiteral);
            try {
                return { ok: true, count: document.querySelectorAll(selector).length };
            } catch (error) {
                return { ok: false, error: 'Invalid selector: ' + selector };
            }
            """
        )
        let result = try await evaluate(script, in: webView)
        let dictionary = try resultDictionary(from: result)
        guard let count = (dictionary["count"] as? NSNumber)?.intValue ?? dictionary["count"] as? Int else {
            throw SheetInteractionError.executionFailed("Invalid count result")
        }
        return count
    }

    static func isVisible(target: String, in webView: WKWebView) async throws -> Bool {
        let result = try await stateValue(target: target, expression: "denIsVisible(el)", in: webView)
        guard let visible = (result as? NSNumber)?.boolValue ?? result as? Bool else {
            throw SheetInteractionError.executionFailed("Invalid visible result")
        }
        return visible
    }

    static func isEnabled(target: String, in webView: WKWebView) async throws -> Bool {
        let result = try await stateValue(
            target: target,
            expression: "denDisabled(el) !== true",
            in: webView
        )
        guard let enabled = (result as? NSNumber)?.boolValue ?? result as? Bool else {
            throw SheetInteractionError.executionFailed("Invalid enabled result")
        }
        return enabled
    }

    static func isChecked(target: String, in webView: WKWebView) async throws -> Bool {
        let result = try await stateValue(target: target, expression: "denChecked(el)", in: webView)
        guard
            let checked = (result as? NSNumber)?.boolValue ?? result as? Bool
        else {
            throw SheetInteractionError.executionFailed("Element does not expose checked state: \(target)")
        }
        return checked
    }

    static func press(key: String, in webView: WKWebView) async throws {
        let keyLiteral = try javascriptLiteral(key)
        let script = """
            (() => {
                const key = \(keyLiteral);
                const el = document.activeElement || document.body;
                const keyCodes = {
                    Enter: 13,
                    Escape: 27,
                    Tab: 9,
                    ArrowDown: 40,
                    ArrowLeft: 37,
                    ArrowRight: 39,
                    ArrowUp: 38,
                    Backspace: 8,
                    Delete: 46,
                    Home: 36,
                    End: 35,
                    PageDown: 34,
                    PageUp: 33,
                    Space: 32,
                };
                const keyCode = keyCodes[key] || (key === ' ' ? 32 : 0);
                const keyData = {
                    key: key,
                    code: key === ' ' ? 'Space' : key,
                    bubbles: true,
                    cancelable: true,
                    view: window
                };
                const makeKeyboardEvent = type => {
                    const event = new KeyboardEvent(type, keyData);
                    if (keyCode) {
                        Object.defineProperty(event, 'keyCode', { value: keyCode });
                        Object.defineProperty(event, 'which', { value: keyCode });
                    }
                    return event;
                };
                el.dispatchEvent(makeKeyboardEvent('keydown'));
                el.dispatchEvent(makeKeyboardEvent('keypress'));
                el.dispatchEvent(makeKeyboardEvent('keyup'));
                if (key === 'Enter') {
                    if (el.form && typeof el.form.requestSubmit === 'function') {
                        el.form.requestSubmit();
                    } else if (el.tagName === 'A' && typeof el.click === 'function') {
                        el.click();
                    }
                }
                return { ok: true };
            })()
            """
        _ = try await webView.evaluateJavaScript(script)
    }

    static func scroll(direction: String, in webView: WKWebView) async throws -> String {
        let script: String
        switch direction.lowercased() {
        case "down":
            script = "window.scrollBy({ top: window.innerHeight * 0.8, behavior: 'instant' })"
        case "up":
            script = "window.scrollBy({ top: -window.innerHeight * 0.8, behavior: 'instant' })"
        case "top":
            script = "window.scrollTo({ top: 0, behavior: 'instant' })"
        case "bottom":
            script = "window.scrollTo({ top: document.body.scrollHeight, behavior: 'instant' })"
        default:
            if let amount = Double(direction) {
                script = "window.scrollBy({ top: \(amount), behavior: 'instant' })"
                _ = try await evaluate(script, in: webView)
                return "Scrolled \(direction)"
            }
            let targetLiteral = try javascriptLiteral(direction)
            let targetScript = operationScript(
                """
                const target = \(targetLiteral);
                let el;
                try {
                    el = denResolveTarget(target);
                } catch (error) {
                    return { ok: false, error: 'Invalid selector: ' + target };
                }
                if (!el) return { ok: false, error: 'Element not found: ' + target };
                el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                return { ok: true };
                """
            )
            let result = try await evaluate(targetScript, in: webView)
            _ = try resultDictionary(from: result)
            return "Scrolled to \(direction)"
        }
        _ = try await evaluate(script, in: webView)
        return "Scrolled \(direction)"
    }

    private static func stateValue(
        target: String,
        expression: String,
        in webView: WKWebView
    ) async throws -> Any? {
        let targetLiteral = try javascriptLiteral(target)
        let script = operationScript(
            """
            const target = \(targetLiteral);
            let el;
            try {
                el = denResolveTarget(target);
            } catch (error) {
                return { ok: false, error: 'Invalid selector: ' + target };
            }
            if (!el) return { ok: false, error: 'Element not found: ' + target };
            return { ok: true, value: \(expression) };
            """
        )
        let result = try await evaluate(script, in: webView)
        let dictionary = try resultDictionary(from: result)
        return dictionary["value"]
    }

    static func waitForElement(
        target: String,
        state: SheetWaitState = .attached,
        in webView: WKWebView,
        timeout: TimeInterval = 10.0
    ) async throws {
        let targetLiteral = try javascriptLiteral(target)
        let stateLiteral = try javascriptLiteral(state.rawValue)
        let checkScript = operationScript(
            """
            const target = \(targetLiteral);
            const state = \(stateLiteral);
            let elements;
            try {
                if (target.startsWith('@')) {
                    const element = denResolveTarget(target);
                    elements = element ? [element] : [];
                } else {
                    elements = Array.from(document.querySelectorAll(target));
                }
            } catch (error) {
                return { ok: false, error: 'Invalid selector: ' + target };
            }

            const matched = state === 'attached'
                ? elements.length > 0
                : state === 'visible'
                    ? elements.some(denIsVisible)
                    : state === 'hidden'
                        ? elements.length === 0 || elements.every(element => !denIsVisible(element))
                        : elements.length === 0;
            return { ok: true, matched: matched };
            """
        )
        try await waitForMatch(checkScript: checkScript, description: target, in: webView, timeout: timeout)
    }

    static func waitForURL(
        pattern: String,
        in webView: WKWebView,
        timeout: TimeInterval = 10.0
    ) async throws {
        let patternLiteral = try javascriptLiteral(pattern)
        let checkScript = operationScript(
            """
            const pattern = \(patternLiteral);
            const value = location.href || '';
            const parts = pattern.split('*');
            let matched = true;
            let cursor = 0;
            if (parts.length === 1) {
                matched = value === pattern;
            } else {
                if (parts[0] && !value.startsWith(parts[0])) matched = false;
                cursor = parts[0].length;
                for (let index = 1; matched && index < parts.length - 1; index++) {
                    if (!parts[index]) continue;
                    const found = value.indexOf(parts[index], cursor);
                    if (found < 0) {
                        matched = false;
                    } else {
                        cursor = found + parts[index].length;
                    }
                }
                const suffix = parts[parts.length - 1];
                if (matched && suffix && (!value.endsWith(suffix) || value.length - suffix.length < cursor)) {
                    matched = false;
                }
            }
            return { ok: true, matched: matched };
            """
        )
        try await waitForMatch(
            checkScript: checkScript,
            description: "URL \(pattern)",
            in: webView,
            timeout: timeout
        )
    }

    static func waitForText(
        text: String,
        in webView: WKWebView,
        timeout: TimeInterval = 10.0
    ) async throws {
        let textLiteral = try javascriptLiteral(text)
        let checkScript = operationScript(
            """
            const expected = \(textLiteral);
            const matched = (document.body?.innerText || '').includes(expected);
            return { ok: true, matched: matched };
            """
        )
        try await waitForMatch(
            checkScript: checkScript,
            description: "text \(text)",
            in: webView,
            timeout: timeout
        )
    }

    static func waitForLoadState(
        _ state: SheetLoadState,
        in webView: WKWebView,
        timeout: TimeInterval = 10.0
    ) async throws {
        let stateLiteral = try javascriptLiteral(state.rawValue)
        let checkScript = operationScript(
            """
            const state = \(stateLiteral);
            const ready = document.readyState;
            let matched = state === 'domcontentloaded'
                ? ready !== 'loading'
                : ready === 'complete';
            if (state === 'networkidle') {
                const resources = performance.getEntriesByType('resource')
                    .map(entry => entry.name + ':' + entry.responseEnd)
                    .join('|');
                const now = performance.now();
                const previous = window.__denNetworkIdleSample;
                if (!previous || previous.resources !== resources) {
                    window.__denNetworkIdleSample = { resources: resources, at: now };
                    matched = false;
                } else {
                    matched = ready === 'complete' && now - previous.at >= 500;
                }
            }
            return { ok: true, matched: matched };
            """
        )
        try await waitForMatch(
            checkScript: checkScript,
            description: "load state \(state.rawValue)",
            in: webView,
            timeout: timeout
        )
    }

    static func waitForFunction(
        expression: String,
        in webView: WKWebView,
        timeout: TimeInterval = 10.0
    ) async throws {
        let checkScript = """
            (() => {
            let matched = false;
            try {
                matched = Boolean(\(expression));
            } catch (error) {
                matched = false;
            }
            return { ok: true, matched: matched };
            })()
            """
        try await waitForMatch(
            checkScript: checkScript,
            description: "function \(expression)",
            in: webView,
            timeout: timeout,
            inPageWorld: true
        )
    }

    private static func waitForMatch(
        checkScript: String,
        description: String,
        in webView: WKWebView,
        timeout: TimeInterval,
        inPageWorld: Bool = false
    ) async throws {
        guard timeout.isFinite, timeout >= 0 else {
            throw SheetInteractionError.invalidArgument("Timeout must be a finite non-negative number")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            do {
                let result: Any?
                if inPageWorld {
                    result = try await webView.evaluateJavaScript(checkScript)
                } else {
                    result = try await evaluate(checkScript, in: webView)
                }
                let dictionary = try resultDictionary(from: result)
                if let matched = (dictionary["matched"] as? NSNumber)?.boolValue ?? (dictionary["matched"] as? Bool),
                    matched
                {
                    return
                }
            } catch let error as SheetInteractionError {
                throw error
            } catch {
                // Navigation can temporarily invalidate a WebKit evaluation. Retry until the deadline.
            }

            if Date() >= deadline { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw SheetInteractionError.timedOut(description)
    }

    private static func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        let result: SheetJavaScriptResult = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(
                script,
                in: nil,
                in: SheetDOMRuntime.contentWorld
            ) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: SheetJavaScriptResult(value))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        return result.value
    }

    private static func operationScript(_ body: String) -> String {
        """
        (() => {
        const dom = window.__denSheetDOM;
        if (!dom) return { ok: false, error: 'Sheet DOM runtime unavailable' };
        const {
            denNormalize,
            denIsVisible,
            denRefFor,
            denResolveRef,
            denResolveTarget,
            denRole,
            denText,
            denAccessibleName,
            denValue,
            denChecked,
            denDisabled,
            denSelected,
            denExpanded,
            denSnapshotStates,
            denSnapshotEligible,
            denSnapshotName,
            denSnapshotLevel,
            denSetValue,
            denInspect,
        } = dom;
        \(body)
        })()
        """
    }

    private static func javascriptLiteral<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let literal = String(data: data, encoding: .utf8) else {
            throw SheetInteractionError.executionFailed("Failed to encode JavaScript argument")
        }
        return literal
    }

    private static func resultDictionary(from evalResult: Any?) throws -> [String: Any] {
        guard let dictionary = evalResult as? [String: Any] else {
            throw SheetInteractionError.executionFailed("Invalid evaluation result")
        }
        if let isSuccess = dictionary["ok"] as? Bool, !isSuccess {
            let message = dictionary["error"] as? String ?? "Operation failed"
            throw SheetInteractionError.executionFailed(message)
        }
        return dictionary
    }

    private static func extractRect(from evalResult: Any?, scale: CGFloat = 1) throws -> CGRect {
        let dictionary = try resultDictionary(from: evalResult)
        guard let rect = dictionary["rect"] as? [String: Any],
            let originX = (rect["x"] as? NSNumber)?.doubleValue,
            let originY = (rect["y"] as? NSNumber)?.doubleValue,
            let width = (rect["width"] as? NSNumber)?.doubleValue,
            let height = (rect["height"] as? NSNumber)?.doubleValue
        else {
            return .zero
        }
        return CGRect(
            x: originX * scale,
            y: originY * scale,
            width: width * scale,
            height: height * scale
        )
    }

    private static func elementInfo(from rawElement: Any) throws -> DenSheetElementInfo {
        guard let dictionary = rawElement as? [String: Any],
            let ref = dictionary["ref"] as? String
        else {
            throw SheetInteractionError.executionFailed("Invalid query element")
        }

        let attributes: [String: String]? = {
            if let rawAttributes = dictionary["attributes"] as? [String: String] {
                return rawAttributes
            }
            guard let rawAttributes = dictionary["attributes"] as? [String: Any] else {
                return nil
            }
            let attributes = rawAttributes.compactMapValues { $0 as? String }
            return attributes.isEmpty ? nil : attributes
        }()
        let visible =
            (dictionary["visible"] as? NSNumber)?.boolValue
            ?? (dictionary["visible"] as? Bool)
            ?? false
        let checked =
            (dictionary["checked"] as? NSNumber)?.boolValue
            ?? (dictionary["checked"] as? Bool)
        let disabled =
            (dictionary["disabled"] as? NSNumber)?.boolValue
            ?? (dictionary["disabled"] as? Bool)
        let selected =
            (dictionary["selected"] as? NSNumber)?.boolValue
            ?? (dictionary["selected"] as? Bool)
        let expanded =
            (dictionary["expanded"] as? NSNumber)?.boolValue
            ?? (dictionary["expanded"] as? Bool)

        return DenSheetElementInfo(
            ref: ref,
            tag: dictionary["tag"] as? String,
            role: dictionary["role"] as? String,
            name: dictionary["name"] as? String,
            text: dictionary["text"] as? String,
            value: dictionary["value"] as? String,
            checked: checked,
            disabled: disabled,
            selected: selected,
            expanded: expanded,
            visible: visible,
            attributes: attributes
        )
    }
}
