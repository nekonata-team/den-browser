import AppKit
import SwiftUI

struct ProfileWindowView: View {
    let profileID: UUID

    @Environment(ProfileManager.self) private var profileManager

    var body: some View {
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
            .background(WindowRegistration(profileID: activeProfileID))
            .toolbarVisibility(store.isZenViewPresented ? .hidden : .visible, for: .windowToolbar)
            .ignoresSafeArea(.container, edges: store.isZenViewPresented ? .top : [])
            .onOpenURL { url in
                store.addBoard(urlString: url.absoluteString)
            }
        } else {
            ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
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

private struct WindowRegistration: NSViewRepresentable {
    let profileID: UUID
    @Environment(ProfileManager.self) private var profileManager

    func makeCoordinator() -> Coordinator {
        Coordinator(profileID: profileID, profileManager: profileManager)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.register(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.register(view.window) }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.unregister()
    }

    @MainActor
    final class Coordinator: NSObject {
        private let profileID: UUID
        private weak var profileManager: ProfileManager?
        private weak var window: NSWindow?

        init(profileID: UUID, profileManager: ProfileManager) {
            self.profileID = profileID
            self.profileManager = profileManager
            super.init()
        }

        func register(_ window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowFocusChanged), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowFocusChanged), name: NSWindow.didResignKeyNotification, object: window)
            profileManager?.register(window: window, for: profileID)
        }

        @objc private func windowFocusChanged(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            DispatchQueue.main.async { [weak window] in
                window?.titlebarAppearsTransparent = true
            }
        }

        func unregister() {
            guard let window else { return }
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            profileManager?.unregister(window: window, for: profileID)
            self.window = nil
        }
    }
}

struct DenStoreFocusedValueKey: FocusedValueKey {
    typealias Value = DenStore
}

extension FocusedValues {
    var denStore: DenStore? {
        get { self[DenStoreFocusedValueKey.self] }
        set { self[DenStoreFocusedValueKey.self] = newValue }
    }
}
