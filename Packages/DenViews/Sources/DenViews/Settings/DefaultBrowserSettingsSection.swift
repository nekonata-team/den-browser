import DenDomain
import DenModels
import SwiftUI

public struct DefaultBrowserSettingsSection: View {
    @State private var model: DefaultBrowserSettingsModel

    public init(model: DefaultBrowserSettingsModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Section("External Links") {
            LabeledContent("Default web browser") {
                Text(model.status.label)
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
                Button(model.status.isDenBrowser ? "Den Browser Is Default" : "Make Den Browser Default") {
                    Task { await model.makeDefaultBrowser() }
                }
                .disabled(model.status.isDenBrowser || model.isSettingDefault)
            }
        }
        .task {
            await model.refreshStatus()
        }
        .alert("Could Not Set Default Browser", isPresented: errorAlertBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding {
            model.errorMessage != nil
        } set: { isPresented in
            if !isPresented { model.errorMessage = nil }
        }
    }

    private var externalLinkDestinationBinding: Binding<ExternalLinkDestination> {
        Binding {
            model.externalLinkDestination
        } set: { destination in
            model.setExternalLinkDestination(destination)
        }
    }

    private var externalLinkDestinationDescription: String {
        switch model.externalLinkDestination {
        case .drawerPeek:
            "Links opened from other apps enter the Drawer as a new Drawer Peek."
        case .focusedBoard:
            "Links opened from other apps create a new Board to the right of the Focused Board."
        }
    }
}
