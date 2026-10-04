import AppKit
import Foundation
import WebKit

enum WebNavigationPolicy {
    static func shouldOpenExternalApplication(
        navigationType: WKNavigationType,
        url: URL?
    ) -> Bool {
        (navigationType == .linkActivated || navigationType == .other)
            && url.map(ExternalURLPolicy.isSupported) == true
    }

    static func shouldOpenLinkInNewBoard(
        navigationType: WKNavigationType,
        modifierFlags: NSEvent.ModifierFlags,
        button: MouseButton?,
        url: URL?
    ) -> Bool {
        let clickModifiers = modifierFlags.intersection([.command, .control, .option, .shift])
        return navigationType == .linkActivated
            && ((button == .primary && (clickModifiers == .command || clickModifiers == [.command, .shift]))
                || (button == .middle && (clickModifiers == [] || clickModifiers == [.shift])))
            && url.map(WebURLPolicy.isSupported) == true
    }

    static func shouldKeepLinkInDrawer(
        navigationType: WKNavigationType,
        modifierFlags: NSEvent.ModifierFlags,
        button: MouseButton?,
        url: URL?
    ) -> Bool {
        let clickModifiers = modifierFlags.intersection([.command, .control, .option, .shift])
        return navigationType == .linkActivated
            && button == .primary
            && clickModifiers == .option
            && url.map(WebURLPolicy.isSupported) == true
    }

    static func shouldOpenTargetlessNavigationInNewBoard(
        navigationType: WKNavigationType,
        url: URL?
    ) -> Bool {
        navigationType == .linkActivated
            && url.map(WebURLPolicy.isSupported) == true
    }
}
