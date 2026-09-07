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
            return "Timed out waiting for element: \(target)"
        case .invalidArgument(let message):
            return message
        }
    }
}

@MainActor
enum SheetInteraction {
    static func snapshot(in webView: WKWebView, interactiveOnly: Bool) async throws -> String {
        let script = """
            (() => {
                const interactiveOnly = \(interactiveOnly);
                window.__denRefs = window.__denRefs || new Map();
                window.__denRefs.clear();
                let refIndex = 1;

                function isVisible(el) {
                    if (!el || el.nodeType !== 1) return false;
                    const rect = el.getBoundingClientRect();
                    if (rect.width === 0 && rect.height === 0) return false;
                    const style = window.getComputedStyle(el);
                    if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
                    return true;
                }

                const selectors = [
                    'a[href]', 'button', 'input', 'select', 'textarea',
                    '[role="button"]', '[role="link"]', '[role="checkbox"]', '[role="menuitem"]',
                    '[role="tab"]', '[role="switch"]', '[tabindex]:not([tabindex="-1"])',
                    'summary', '[contenteditable="true"]'
                ];

                const elements = Array.from(document.querySelectorAll(selectors.join(',')));
                const lines = [];

                for (const el of elements) {
                    if (!isVisible(el)) continue;
                    const ref = `@e${refIndex++}`;
                    window.__denRefs.set(ref, el);
                    el.setAttribute('data-den-ref', ref);

                    const tag = el.tagName.toLowerCase();
                    const role = el.getAttribute('role') || tag;
                    const type = el.getAttribute('type') || '';
                    const text = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('placeholder') || el.value || '').trim().replace(/\\s+/g, ' ');
                    const truncatedText = text.length > 50 ? text.slice(0, 47) + '...' : text;

                    let desc = `${ref} [${role}${type ? `:${type}` : ''}]`;
                    if (truncatedText) {
                        desc += ` "${truncatedText}"`;
                    }
                    lines.push(desc);
                }

                return lines.join('\\n');
            })()
            """
        let evalResult = try await webView.evaluateJavaScript(script)
        return "\(evalResult ?? "")"
    }

    static func click(target: String, in webView: WKWebView) async throws {
        let escapedTarget = target.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
            of: "\"", with: "\\\"")
        let script = """
            ((target) => {
                let el = null;
                if (target.startsWith('@')) {
                    el = (window.__denRefs && window.__denRefs.get(target)) || document.querySelector(`[data-den-ref="${target}"]`);
                } else {
                    el = document.querySelector(target);
                }
                if (!el) return { ok: false, error: `Element not found: ${target}` };
                el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                el.focus();
                const mousedown = new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window });
                const mouseup = new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window });
                const click = new MouseEvent('click', { bubbles: true, cancelable: true, view: window });
                el.dispatchEvent(mousedown);
                el.dispatchEvent(mouseup);
                el.dispatchEvent(click);
                if (typeof el.click === 'function') el.click();
                return { ok: true };
            })("\(escapedTarget)")
            """
        let evalResult = try await webView.evaluateJavaScript(script)
        if let dict = evalResult as? [String: Any], let isSuccess = dict["ok"] as? Bool, !isSuccess {
            let errMsg = (dict["error"] as? String) ?? "Failed to click element"
            throw SheetInteractionError.executionFailed(errMsg)
        }
    }

    static func fill(target: String, value: String, in webView: WKWebView) async throws {
        let escapedTarget = target.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
            of: "\"", with: "\\\"")
        let escapedValue = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
            of: "\"", with: "\\\"")
        let script = """
            ((target, value) => {
                let el = null;
                if (target.startsWith('@')) {
                    el = (window.__denRefs && window.__denRefs.get(target)) || document.querySelector(`[data-den-ref="${target}"]`);
                } else {
                    el = document.querySelector(target);
                }
                if (!el) return { ok: false, error: `Element not found: ${target}` };
                el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
                el.focus();
                el.value = value;
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                return { ok: true };
            })("\(escapedTarget)", "\(escapedValue)")
            """
        let evalResult = try await webView.evaluateJavaScript(script)
        if let dict = evalResult as? [String: Any], let isSuccess = dict["ok"] as? Bool, !isSuccess {
            let errMsg = (dict["error"] as? String) ?? "Failed to fill element"
            throw SheetInteractionError.executionFailed(errMsg)
        }
    }

    static func press(key: String, in webView: WKWebView) async throws {
        let escapedKey = key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
            of: "\"", with: "\\\"")
        let script = """
            ((key) => {
                const el = document.activeElement || document.body;
                const keyData = {
                    key: key,
                    code: key === ' ' ? 'Space' : key,
                    bubbles: true,
                    cancelable: true,
                    view: window
                };
                el.dispatchEvent(new KeyboardEvent('keydown', keyData));
                el.dispatchEvent(new KeyboardEvent('keypress', keyData));
                el.dispatchEvent(new KeyboardEvent('keyup', keyData));
                if (key === 'Enter') {
                    if (el.form && typeof el.form.requestSubmit === 'function') {
                        el.form.requestSubmit();
                    } else if (el.tagName === 'A' && typeof el.click === 'function') {
                        el.click();
                    }
                }
                return { ok: true };
            })("\(escapedKey)")
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
            guard let amount = Double(direction) else {
                throw SheetInteractionError.invalidArgument(
                    "Invalid scroll direction: '\(direction)'. Use down, up, top, bottom, or pixel number.")
            }
            script = "window.scrollBy({ top: \(amount), behavior: 'instant' })"
        }
        _ = try await webView.evaluateJavaScript(script)
        return "Scrolled \(direction)"
    }

    static func waitForElement(
        target: String,
        in webView: WKWebView,
        timeout: TimeInterval = 10.0
    ) async throws {
        let escapedTarget = target.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
            of: "\"", with: "\\\"")
        let checkScript = """
            ((target) => {
                if (target.startsWith('@')) {
                    return !!((window.__denRefs && window.__denRefs.get(target)) || document.querySelector(`[data-den-ref="${target}"]`));
                }
                return !!document.querySelector(target);
            })("\(escapedTarget)")
            """
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = try? await webView.evaluateJavaScript(checkScript) as? Bool, result {
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw SheetInteractionError.timedOut(target)
    }
}
