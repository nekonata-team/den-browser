import AppKit
import DenModels
import Foundation

enum DefaultBrowserSystem {
    nonisolated static let urlSchemes = ["http", "https"]
    nonisolated static func status() -> DefaultBrowserStatus {
        let applications: [URL] = urlSchemes.compactMap { scheme -> URL? in
            guard let url = URL(string: "\(scheme)://example.com") else { return nil }
            return NSWorkspace.shared.urlForApplication(toOpen: url)
        }
        guard applications.count == urlSchemes.count else { return .unavailable }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return .unavailable }
        if applications.allSatisfy({ Bundle(url: $0)?.bundleIdentifier == bundleIdentifier }) {
            return .denBrowser
        }

        let names = Set(applications.map { $0.deletingPathExtension().lastPathComponent })
        guard names.count == 1, let name = names.first else { return .mixed }
        return .other(name)
    }
    @MainActor
    static func makeDefault() async {
        let applicationURL = Bundle.main.bundleURL
        for scheme in urlSchemes {
            await withCheckedContinuation { continuation in
                NSWorkspace.shared.setDefaultApplication(at: applicationURL, toOpenURLsWithScheme: scheme) { _ in
                    continuation.resume()
                }
            }
        }
    }
}
