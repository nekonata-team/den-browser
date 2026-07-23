import AppKit
import SwiftUI

struct DefaultBrowserSettingsSection: View {
    @State private var status: DefaultBrowserStatus = .loading
    @State private var isSettingDefault = false
    @State private var errorMessage: String?

    var body: some View {
        Section("External Links") {
            LabeledContent("Default web browser") {
                Text(status.label)
                    .foregroundStyle(.secondary)
            }

            Button(status.isDenBrowser ? "Den Browser Is Default" : "Make Den Browser Default") {
                makeDefaultBrowser()
            }
            .disabled(status.isDenBrowser || isSettingDefault)

            // TODO: Update copy when external links enter the Drawer instead of the Focused Desk.
            // See ADR 0025: docs/adr/0025-den-level-drawer-for-unplaced-material.md
            Text("Links opened from other apps will open as a new Board in the Focused Desk.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshStatus)
        .alert("Could Not Set Default Browser", isPresented: errorAlertBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding {
            errorMessage != nil
        } set: { isPresented in
            if !isPresented { errorMessage = nil }
        }
    }

    private func refreshStatus() {
        status = .fromDefaultApplications()
    }

    private func makeDefaultBrowser() {
        let applicationURL = Bundle.main.bundleURL
        isSettingDefault = true

        Task { @MainActor in
            var failed = false
            for scheme in DefaultBrowserStatus.urlSchemes {
                if await Self.setDefaultApplication(applicationURL, for: scheme) != nil {
                    failed = true
                }
            }

            isSettingDefault = false
            refreshStatus()
            if failed {
                errorMessage = "macOS did not accept the change. You can set the default browser in System Settings."
            }
        }
    }

    private static func setDefaultApplication(_ applicationURL: URL, for scheme: String) async -> Error? {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.setDefaultApplication(
                at: applicationURL,
                toOpenURLsWithScheme: scheme
            ) { error in
                continuation.resume(returning: error)
            }
        }
    }
}

private enum DefaultBrowserStatus {
    static let urlSchemes = ["http", "https"]

    case loading
    case denBrowser
    case other(String)
    case mixed
    case unavailable

    var label: String {
        switch self {
        case .loading: "Checking…"
        case .denBrowser: "Den Browser"
        case .other(let name): name
        case .mixed: "Different apps"
        case .unavailable: "Unavailable"
        }
    }

    var isDenBrowser: Bool {
        if case .denBrowser = self { return true }
        return false
    }

    static func fromDefaultApplications() -> Self {
        let applications: [URL] = urlSchemes.compactMap { scheme -> URL? in
            guard let url = URL(string: "\(scheme)://example.com") else { return nil }
            return NSWorkspace.shared.urlForApplication(toOpen: url)
        }
        guard applications.count == urlSchemes.count else { return .unavailable }

        if applications.allSatisfy({ $0.path == Bundle.main.bundleURL.path }) {
            return .denBrowser
        }

        let names = Set(applications.map { $0.deletingPathExtension().lastPathComponent })
        guard names.count == 1, let name = names.first else { return .mixed }
        return .other(name)
    }
}
