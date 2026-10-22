import AppKit
import DenDomain
import DenPresentationModels
import DenViews
import SFSafeSymbols
import SwiftUI

struct SettingsView: View {
    @State private var selection: SettingsSection? = .profiles

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemSymbol: section.systemSymbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch selection ?? .profiles {
                case .profiles:
                    ProfilesSettingsView()
                case .appearance:
                    AppearanceSettingsView(
                        sheetScaleRange: AppPreferences.sheetScaleRange,
                        defaultSheetScale: AppPreferences.defaultSheetScale)
                case .shortcuts:
                    ShortcutsSettingsView()
                case .essentials:
                    EssentialsSettingsView()
                case .terminal:
                    TerminalSettingsView()
                case .web:
                    WebSettingsView()
                case .features:
                    FeaturesSettingsView()
                }
            }
            .navigationTitle((selection ?? .profiles).title)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 560)
        .onDisappear {
            NSColorPanel.shared.close()
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case profiles
    case appearance
    case shortcuts
    case essentials
    case terminal
    case web
    case features

    var id: Self { self }

    var title: String {
        switch self {
        case .profiles:
            "Profiles"
        case .appearance:
            "Appearance"
        case .shortcuts:
            "Shortcuts"
        case .essentials:
            "Essentials"
        case .terminal:
            "Terminal"
        case .web:
            "Web"
        case .features:
            "Features"
        }
    }

    var systemSymbol: SFSymbol {
        switch self {
        case .profiles:
            .person2
        case .appearance:
            .circleLefthalfFilled
        case .shortcuts:
            .keyboard
        case .essentials:
            .sparkles
        case .terminal:
            .appleTerminal
        case .web:
            .globe
        case .features:
            .puzzlepiece
        }
    }
}

private struct WebSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(ProfileManager.self) private var profileManager
    @State private var uBOLitePopupAnchorView: NSView?

    var body: some View {
        SettingsForm {
            DefaultBrowserSettingsSection(model: DefaultBrowserSettingsModel(preferences: preferences))

            Section("Search") {
                Picker(
                    "Search Engine",
                    selection: Binding(get: { preferences.searchEngine }, set: { preferences.setSearchEngine($0) })
                ) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                SettingsHelpText {
                    Text("Used for search terms across all Profiles. Existing Sheets stay unchanged.")
                }
            }

            SheetNavigationSettingsSection()

            Section("Picture in Picture") {
                Toggle(
                    "Automatic Picture in Picture",
                    isOn: automaticPIPOnDeskSwitchBinding)
                SettingsHelpText {
                    Text(
                        "When switching Desks, move a playing video from the Focused Board into Picture in Picture."
                    )
                }
            }

            Section("Content Blocking") {
                if profileManager.uboliteInstaller.isInstalled {
                    LabeledContent {
                        Toggle("", isOn: uBOLiteBinding)
                            .labelsHidden()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("uBlock Origin Lite")
                            SettingsHelpText {
                                Text("Use MV3 content blocking on every Sheet.")
                            }
                            Text("Changing this setting reloads open Sheets.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if preferences.uBOLiteEnabled {
                        SettingsActionRow {
                            Button {
                                profileManager.presentUBOLitePopup(anchorView: uBOLitePopupAnchorView)
                            } label: {
                                Label("Open uBlock Origin Lite", systemSymbol: .shieldLefthalfFilled)
                            }
                            .background(
                                PopupAnchorView { view in
                                    guard uBOLitePopupAnchorView !== view else { return }
                                    uBOLitePopupAnchorView = view
                                }
                                .allowsHitTesting(false)
                            )

                            Button {
                                profileManager.presentUBOLiteOptions()
                            } label: {
                                Label("Open Settings Dashboard", systemSymbol: .gearshape)
                            }
                        }
                    }

                    if let version = profileManager.uboliteInstaller.installedVersion {
                        SettingsHelpText {
                            Text("Installed version: \(version)")
                        }
                    }

                    SettingsActionRow {
                        Button {
                            Task {
                                await profileManager.updateUBOLite()
                            }
                        } label: {
                            if profileManager.uboliteInstaller.isBusy {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Updating…")
                                }
                            } else {
                                Label("Check for Updates", systemSymbol: .arrowTrianglehead2ClockwiseRotate90)
                            }
                        }
                        .disabled(profileManager.uboliteInstaller.isBusy)

                        Button("Uninstall uBlock Origin Lite", role: .destructive) {
                            profileManager.setUBOLiteEnabled(false)
                            profileManager.uboliteInstaller.uninstall()
                        }
                        .disabled(profileManager.uboliteInstaller.isBusy)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("uBlock Origin Lite")
                        SettingsHelpText {
                            Text(
                                "Fast, efficient MV3 content blocker. Download and install to enable content blocking across Sheets."
                            )
                        }

                        Button {
                            Task {
                                let success = await profileManager.uboliteInstaller.install()
                                if success {
                                    profileManager.setUBOLiteEnabled(true)
                                }
                            }
                        } label: {
                            if profileManager.uboliteInstaller.isBusy {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Installing…")
                                }
                            } else {
                                Label("Install uBlock Origin Lite", systemSymbol: .arrowDownCircle)
                            }
                        }
                        .disabled(profileManager.uboliteInstaller.isBusy)
                    }
                }

                if case .error(let message) = profileManager.uboliteInstaller.state {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var uBOLiteBinding: Binding<Bool> {
        Binding {
            preferences.uBOLiteEnabled
        } set: { enabled in
            profileManager.setUBOLiteEnabled(enabled)
        }
    }

    private var automaticPIPOnDeskSwitchBinding: Binding<Bool> {
        Binding {
            preferences.automaticPIPOnDeskSwitch
        } set: { enabled in
            preferences.setAutomaticPIPOnDeskSwitch(enabled)
        }
    }
}

private struct PopupAnchorView: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(view) }
    }
}
