import AppKit
import SwiftUI

struct DefaultBrowserSettingsSection: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var status: DefaultBrowserStatus = .loading
    @State private var isSettingDefault = false
    @State private var errorMessage: String?

    var body: some View {
        Section("External Links") {
            LabeledContent("Default web browser") {
                Text(status.label)
                    .foregroundStyle(.secondary)
            }

            Picker("Open links in", selection: externalLinkDestinationBinding) {
                ForEach(ExternalLinkDestination.allCases) { destination in
                    Text(destination.label).tag(destination)
                }
            }

            SettingsHelpText {
                Text(externalLinkDestinationDescription)
            }

            SettingsActionRow {
                Button(status.isDenBrowser ? "Den Browser Is Default" : "Make Den Browser Default") {
                    makeDefaultBrowser()
                }
                .disabled(status.isDenBrowser || isSettingDefault)
            }
        }
        .task {
            await refreshStatus()
        }
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

    private var externalLinkDestinationBinding: Binding<ExternalLinkDestination> {
        Binding {
            preferences.externalLinkDestination
        } set: { destination in
            preferences.setExternalLinkDestination(destination)
        }
    }

    private var externalLinkDestinationDescription: String {
        switch preferences.externalLinkDestination {
        case .drawerPreview:
            "Links opened from other apps enter the Drawer as a new Drawer Preview."
        case .focusedBoard:
            "Links opened from other apps create a new Board to the right of the Focused Board."
        }
    }

    private func refreshStatus() async {
        let newStatus = await Task.detached(priority: .userInitiated) {
            DefaultBrowserStatus.fromDefaultApplications()
        }.value
        status = newStatus
    }

    private func makeDefaultBrowser() {
        let applicationURL = Bundle.main.bundleURL
        isSettingDefault = true

        Task { @MainActor in
            for scheme in DefaultBrowserStatus.urlSchemes {
                _ = await Self.setDefaultApplication(applicationURL, for: scheme)
            }

            await refreshStatus()
            isSettingDefault = false
            if !status.isDenBrowser {
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

private enum DefaultBrowserStatus: Sendable {
    nonisolated static let urlSchemes = ["http", "https"]

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

    nonisolated static func fromDefaultApplications() -> Self {
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
}
