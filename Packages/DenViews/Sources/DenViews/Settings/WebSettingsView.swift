public import AppKit
import DenDomain
public import DenModels
import SFSafeSymbols
public import SwiftUI

public struct WebSettingsView: View {
    private let model: WebSettingsModel
    private let defaultBrowser: DefaultBrowserSettingsModel
    private let openPopup: (NSView?) -> Void
    @State private var uBOLitePopupAnchorView: NSView?

    public init(
        model: WebSettingsModel, defaultBrowser: DefaultBrowserSettingsModel, openPopup: @escaping (NSView?) -> Void
    ) {
        self.model = model
        self.defaultBrowser = defaultBrowser
        self.openPopup = openPopup
    }

    public var body: some View {
        SettingsForm {
            DefaultBrowserSettingsSection(model: defaultBrowser)

            Section("Search") {
                Picker(
                    "Search Engine",
                    selection: Binding(get: { model.searchEngine }, set: { model.setSearchEngine($0) })
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
                if model.isInstalled {
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

                    if model.uBOLiteEnabled {
                        SettingsActionRow {
                            Button {
                                openPopup(uBOLitePopupAnchorView)
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
                                model.openOptions()
                            } label: {
                                Label("Open Settings Dashboard", systemSymbol: .gearshape)
                            }
                        }
                    }

                    if let version = model.installedVersion {
                        SettingsHelpText {
                            Text("Installed version: \(version)")
                        }
                    }

                    SettingsActionRow {
                        Button {
                            Task {
                                await model.update()
                            }
                        } label: {
                            if model.isBusy {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Updating…")
                                }
                            } else {
                                Label("Check for Updates", systemSymbol: .arrowTrianglehead2ClockwiseRotate90)
                            }
                        }
                        .disabled(model.isBusy)

                        Button("Uninstall uBlock Origin Lite", role: .destructive) {
                            model.uninstall()
                        }
                        .disabled(model.isBusy)
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
                                await model.install()
                            }
                        } label: {
                            if model.isBusy {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Installing…")
                                }
                            } else {
                                Label("Install uBlock Origin Lite", systemSymbol: .arrowDownCircle)
                            }
                        }
                        .disabled(model.isBusy)
                    }
                }

                if let message = model.errorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var uBOLiteBinding: Binding<Bool> {
        Binding {
            model.uBOLiteEnabled
        } set: { enabled in
            model.setUBOLiteEnabled(enabled)
        }
    }

    private var automaticPIPOnDeskSwitchBinding: Binding<Bool> {
        Binding {
            model.automaticPIPOnDeskSwitch
        } set: { enabled in
            model.setAutomaticPIPOnDeskSwitch(enabled)
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
