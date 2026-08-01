import SwiftUI

struct ProfileWindowView: View {
    let profileID: UUID

    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        content
            .onChange(of: appearsActive, initial: true) { _, isActive in
                profileManager.setProfileActive(profileID, isActive: isActive)
            }
            .onDisappear {
                profileManager.profileWindowDisappeared(profileID)
            }
            .handlesExternalEvents(
                preferring: appearsActive ? ["*"] : [],
                allowing: appearsActive ? [] : ["*"])
    }

    @ViewBuilder
    private var content: some View {
        let activeProfileID = profileManager.resolvedProfileID(profileID)
        if let profile = profileManager.profile(id: activeProfileID),
            let store = profileManager.store(for: activeProfileID)
        {
            ZStack(alignment: .topTrailing) {
                DenView(profileName: profile.name, profileColor: profile.color.color)

                if !store.isZenViewPresented && !store.isOverviewPresented {
                    HStack(spacing: 8) {
                        if store.focusedDesk?.boards.isEmpty == false {
                            Button {
                                store.showSaveDeskPresetPanel()
                            } label: {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.borderless)
                            .tint(.secondary)
                            .fixedSize()
                            .accessibilityLabel("Save Desk as Preset")
                            .help("Save Desk as Preset")
                        }

                        ProfileChip(profile: profile)
                    }
                    .padding(12)
                }

                if profileManager.openProfilePanelProfileID == activeProfileID {
                    OpenProfilePanel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 64)
                }
            }
            .tint(profile.color.color)
            .environment(store)
            .focusedSceneValue(\.denStore, store)
            .focusedSceneValue(\.profileID, activeProfileID)
            .toolbarVisibility(store.isZenViewPresented ? .hidden : .visible, for: .windowToolbar)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .ignoresSafeArea(.container, edges: store.isZenViewPresented ? .top : [])
            .onOpenURL { url in
                store.keepInDrawer(url)
            }
            .sheet(
                isPresented: Binding(
                    get: { profileManager.clearBrowsingDataProfileID != nil },
                    set: { if !$0 { profileManager.clearBrowsingDataProfileID = nil } }
                )
            ) {
                if let id = profileManager.clearBrowsingDataProfileID {
                    ClearBrowsingDataView(profileID: id) {
                        profileManager.clearBrowsingDataProfileID = nil
                    }
                }
            }
        } else {
            ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ProfileChip: View {
    let profile: ProfileState

    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            ForEach(profileManager.profiles) { item in
                Button {
                    openWindow(value: item.id)
                } label: {
                    Label(item.name, systemImage: item.id == profile.id ? "checkmark" : "person.crop.circle")
                }
            }

            Divider()

            Button("Open Profile…") {
                profileManager.openProfilePanelProfileID = profile.id
            }
            .keyboardShortcut("p", modifiers: [.control, .command])

            Button("Clear Browsing Data…") {
                profileManager.clearBrowsingDataProfileID = profile.id
            }

            SettingsLink {
                Text("New Profile…")
            }
            SettingsLink {
                Text("Manage Profiles…")
            }
        } label: {
            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .tint(.secondary)
        .fixedSize()
        .accessibilityLabel("Profile: \(profile.name)")
        .help("Profile: \(profile.name)")
    }
}

private struct OpenProfilePanel: View {
    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Open Profile", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFocused)

            ForEach(filteredProfiles) { profile in
                Button {
                    profileManager.openProfilePanelProfileID = nil
                    openWindow(value: profile.id)
                } label: {
                    HStack {
                        Circle().fill(profile.color.color).frame(width: 10, height: 10)
                        Text(profile.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 5)
            }
        }
        .padding(16)
        .frame(width: 380)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear { isFocused = true }
        .onExitCommand { profileManager.openProfilePanelProfileID = nil }
    }

    private var filteredProfiles: [ProfileState] {
        guard !query.isEmpty else { return profileManager.profiles }
        return profileManager.profiles.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

struct DenStoreFocusedValueKey: FocusedValueKey {
    typealias Value = DenStore
}

struct ProfileIDFocusedValueKey: FocusedValueKey {
    typealias Value = UUID
}

extension FocusedValues {
    var denStore: DenStore? {
        get { self[DenStoreFocusedValueKey.self] }
        set { self[DenStoreFocusedValueKey.self] = newValue }
    }

    var profileID: UUID? {
        get { self[ProfileIDFocusedValueKey.self] }
        set { self[ProfileIDFocusedValueKey.self] = newValue }
    }
}
