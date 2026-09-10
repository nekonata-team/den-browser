import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var selection: SettingsSection? = .profiles

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
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
                    AppearanceSettingsView()
                case .shortcuts:
                    ShortcutsSettingsView()
                case .essentials:
                    EssentialsSettingsView()
                case .terminal:
                    TerminalSettingsView()
                case .web:
                    WebSettingsView()
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
        }
    }

    var systemImage: String {
        switch self {
        case .profiles:
            "person.2"
        case .appearance:
            "circle.lefthalf.filled"
        case .shortcuts:
            "keyboard"
        case .essentials:
            "sparkles"
        case .terminal:
            "terminal"
        case .web:
            "globe"
        }
    }
}

private struct WebSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(ProfileManager.self) private var profileManager
    @State private var uBOLitePopupAnchorView: NSView?

    var body: some View {
        SettingsForm {
            DefaultBrowserSettingsSection()

            Section("Search") {
                Picker(
                    "Search Engine",
                    selection: Binding(get: { preferences.searchEngine }, set: { preferences.setSearchEngine($0) })
                ) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
                SettingsHelpText {
                    Text("Used for search terms across all Profiles. Existing Sheets stay unchanged.")
                }
            }

            SheetNavigationSettingsSection()

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
                                Label("Open uBlock Origin Lite", systemImage: "shield.lefthalf.filled")
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
                                Label("Open Settings Dashboard", systemImage: "gearshape")
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
                                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
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
                                Label("Install uBlock Origin Lite", systemImage: "arrow.down.circle")
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

private struct TerminalSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var zellijPathDraft = ""
    @State private var zmxPathDraft = ""
    @State private var hasLoadedDraft = false

    var body: some View {
        SettingsForm {
            Section("Permissions") {
                SettingsHelpText {
                    Text("Terminal Boards may need Full Disk Access to access protected files.")
                }

                SettingsActionRow {
                    Button("Open Full Disk Access Settings") {
                        openFullDiskAccessSettings()
                    }
                }
            }

            Section("Zellij") {
                TextField(
                    text: $zellijPathDraft,
                    prompt: Text("/usr/local/bin/zellij")
                ) {
                    Text("Executable")
                }
                .onSubmit {
                    TextInputComposition.performUnlessActive(saveZellijPath)
                }

                SettingsHelpText {
                    Text("Use the absolute path to the Zellij executable.")
                }

                SettingsActionRow {
                    Button("Save Executable Path") {
                        saveZellijPath()
                    }
                    .disabled(!hasZellijPathChanges)
                }
            }

            Section("zmx") {
                TextField(
                    text: $zmxPathDraft,
                    prompt: Text("/usr/local/bin/zmx")
                ) {
                    Text("Executable")
                }
                .onSubmit {
                    TextInputComposition.performUnlessActive(saveZmxPath)
                }

                SettingsHelpText {
                    Text("Use the absolute path to the zmx executable.")
                }

                SettingsActionRow {
                    Button("Save Executable Path") {
                        saveZmxPath()
                    }
                    .disabled(!hasZmxPathChanges)
                }
            }
        }
        .onAppear {
            guard !hasLoadedDraft else { return }
            zellijPathDraft = preferences.zellijPath
            zmxPathDraft = preferences.zmxPath
            hasLoadedDraft = true
        }
    }

    private var hasZellijPathChanges: Bool {
        zellijPathDraft.trimmingCharacters(in: .whitespacesAndNewlines) != preferences.zellijPath
    }

    private func saveZellijPath() {
        preferences.setZellijPath(zellijPathDraft)
        zellijPathDraft = preferences.zellijPath
    }

    private var hasZmxPathChanges: Bool {
        zmxPathDraft.trimmingCharacters(in: .whitespacesAndNewlines) != preferences.zmxPath
    }

    private func saveZmxPath() {
        preferences.setZmxPath(zmxPathDraft)
        zmxPathDraft = preferences.zmxPath
    }

    private func openFullDiskAccessSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct AppearanceSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        SettingsForm {
            Section("Board Centering") {
                Picker("Centering", selection: boardCenteringBinding) {
                    ForEach(FocusedBoardCentering.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                SettingsHelpText {
                    Text(boardCenteringDescription)
                }
            }

            Section("Sheet Scale") {
                HStack(spacing: 12) {
                    Text("50%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: sheetScaleBinding,
                        in: Double(
                            AppPreferences.sheetScaleRange.lowerBound)...Double(
                                AppPreferences.sheetScaleRange.upperBound),
                        step: 1)
                    Text("200%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Scale") {
                    Text("\(preferences.sheetScale)%")
                        .monospacedDigit()
                }

                SettingsHelpText {
                    Text("Applies to every Sheet across Profiles immediately.")
                }

                SettingsActionRow {
                    Button("Reset Sheet Scale") {
                        preferences.setSheetScale(AppPreferences.defaultSheetScale)
                    }
                    .disabled(preferences.sheetScale == AppPreferences.defaultSheetScale)
                }
            }

            Section("Motion") {
                Picker("Motion", selection: motionBinding) {
                    ForEach(MotionPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.radioGroup)

                SettingsHelpText {
                    Text(motionDescription)
                }
            }
        }
    }

    private var boardCenteringBinding: Binding<FocusedBoardCentering> {
        Binding {
            preferences.boardCentering
        } set: { mode in
            preferences.setBoardCentering(mode)
        }
    }

    private var boardCenteringDescription: String {
        switch preferences.boardCentering {
        case .always:
            "Keep the focused board centered in the window, even at the ends."
        case .never:
            "Do not center focused Boards. Off-screen Boards scroll only to the nearest edge."
        case .onOverflow:
            "Center a focused Board when it does not fit beside the previously focused Board."
        }
    }

    private var motionBinding: Binding<MotionPreference> {
        Binding {
            preferences.motionPreference
        } set: { preference in
            preferences.setMotionPreference(preference)
        }
    }

    private var sheetScaleBinding: Binding<Double> {
        Binding {
            Double(preferences.sheetScale)
        } set: { scale in
            preferences.setSheetScale(Int(scale.rounded()))
        }
    }

    private var motionDescription: String {
        switch preferences.motionPreference {
        case .followSystem:
            "Use the macOS setting. Reduce Motion is currently \(systemReduceMotion ? "on" : "off")."
        case .standard:
            "Use Den’s standard smooth motion, even when Reduce Motion is enabled in macOS."
        case .reduced:
            "Remove spatial motion and use brief opacity changes."
        }
    }
}

private struct ProfilesSettingsView: View {
    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var newName = ""
    @State private var newColor: ProfileColor = .purple
    @State private var profileToDelete: ProfileState?

    var body: some View {
        SettingsForm {
            Section("Profiles") {
                ForEach(profileManager.profiles) { profile in
                    ProfileSettingsRow(
                        profile: profile,
                        canDelete: profile.webProfileStore != .default,
                        onDelete: { profileToDelete = profile })
                }
            }

            Section("New Profile") {
                HStack {
                    TextField(
                        text: $newName,
                        prompt: Text("e.g. Work")
                    ) {
                        Text("Profile name")
                    }
                    .labelsHidden()
                    .onSubmit {
                        TextInputComposition.performUnlessActive(createProfile)
                    }
                    HStack(spacing: 8) {
                        ColorPicker("Color", selection: newColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .accessibilityLabel("New profile color")
                        ProfileColorPalette(selection: $newColor)
                    }
                }
                SettingsActionRow {
                    Button("Create Profile") {
                        createProfile()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .confirmationDialog(
            "Delete \(profileToDelete?.name ?? "Profile")?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } })
        ) {
            Button("Delete Profile", role: .destructive) {
                guard let profileToDelete else { return }
                Task {
                    if await profileManager.deleteProfile(profileToDelete.id) {
                        dismissWindow(value: profileToDelete.id)
                    }
                    self.profileToDelete = nil
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { profileToDelete = nil }
        } message: {
            Text("Its Den, open window, and website data will be removed.")
        }
        .alert(
            "Profile Error",
            isPresented: Binding(
                get: { profileManager.errorMessage != nil },
                set: { if !$0 { profileManager.clearError() } })
        ) {
            Button("OK") { profileManager.clearError() }
        } message: {
            Text(profileManager.errorMessage ?? "")
        }
        .sheet(
            isPresented: Binding(
                get: {
                    profileManager.clearBrowsingDataProfileID != nil
                        && profileManager.clearBrowsingDataWindowID == nil
                },
                set: {
                    if !$0 {
                        profileManager.clearBrowsingDataProfileID = nil
                        profileManager.clearBrowsingDataWindowID = nil
                    }
                }
            )
        ) {
            if let id = profileManager.clearBrowsingDataProfileID {
                ClearBrowsingDataView(profileID: id) {
                    profileManager.clearBrowsingDataProfileID = nil
                    profileManager.clearBrowsingDataWindowID = nil
                }
            }
        }
    }

    private func createProfile() {
        guard profileManager.createProfile(name: newName, color: newColor) != nil else { return }
        newName = ""
    }

    private var newColorBinding: Binding<Color> {
        Binding {
            newColor.color
        } set: { color in
            if let profileColor = ProfileColor(color: color) {
                newColor = profileColor
            }
        }
    }
}

private struct ProfileColorPalette: View {
    @Binding var selection: ProfileColor

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ProfileColor.presets) { preset in
                Button {
                    selection = preset
                } label: {
                    Circle()
                        .fill(preset.color)
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    Color.primary.opacity(selection == preset ? 0.9 : 0.25),
                                    lineWidth: selection == preset ? 2 : 1)
                        }
                        .padding(2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.label)
                .accessibilityAddTraits(selection == preset ? [.isSelected] : [])
            }
        }
        .fixedSize()
    }
}

private struct ProfileSettingsRow: View {
    let profile: ProfileState
    let canDelete: Bool
    let onDelete: () -> Void

    @Environment(ProfileManager.self) private var profileManager
    @State private var name: String

    init(profile: ProfileState, canDelete: Bool, onDelete: @escaping () -> Void) {
        self.profile = profile
        self.canDelete = canDelete
        self.onDelete = onDelete
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        HStack {
            TextField(
                text: $name,
                prompt: Text("e.g. Work")
            ) {
                Text("Profile name")
            }
            .labelsHidden()
            .onSubmit { TextInputComposition.performUnlessActive(saveName) }
            HStack(spacing: 8) {
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("Profile color for \(profile.name)")
                ProfileColorPalette(selection: profileColorBinding)
            }
            Button {
                profileManager.clearBrowsingDataProfileID = profile.id
                profileManager.clearBrowsingDataWindowID = nil
            } label: {
                Image(systemName: "eraser")
            }
            .buttonStyle(.borderless)
            .help("Clear Browsing Data…")
            .accessibilityLabel("Clear Browsing Data for \(profile.name)")

            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete Profile")
                .accessibilityLabel("Delete Profile \(profile.name)")
            } else {
                Button {
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(true)
                .help("Default Profile (Personal) cannot be deleted")
                .accessibilityLabel("Default Profile (Personal) cannot be deleted")
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding {
            profileColorBinding.wrappedValue.color
        } set: { color in
            guard let profileColor = ProfileColor(color: color) else { return }
            _ = profileManager.updateProfile(profile.id, color: profileColor)
        }
    }

    private var profileColorBinding: Binding<ProfileColor> {
        Binding {
            profileManager.profile(id: profile.id)?.color ?? profile.color
        } set: { color in
            _ = profileManager.updateProfile(profile.id, color: color)
        }
    }

    private func saveName() {
        guard profileManager.updateProfile(profile.id, name: name) else {
            name = profileManager.profile(id: profile.id)?.name ?? profile.name
            return
        }
        name = profileManager.profile(id: profile.id)?.name ?? name
    }

}
