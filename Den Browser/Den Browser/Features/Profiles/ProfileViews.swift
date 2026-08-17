import AppKit
import SwiftUI

struct ProfileWindowView: View {
    let route: ProfileWindowRoute

    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        content
            .handlesExternalEvents(
                preferring: appearsActive ? ["*"] : [],
                allowing: appearsActive ? [] : ["*"]
            )
            .onChange(of: appearsActive, initial: true) { _, isActive in
                guard isActive else { return }
                profileManager.focusWebExtensionWindow(for: route)
            }
    }

    @ViewBuilder
    private var content: some View {
        let activeProfileID = profileManager.resolvedProfileID(route.profileID)
        if let profile = profileManager.profile(id: activeProfileID),
            let store = profileManager.store(for: route)
        {
            ZStack(alignment: .top) {
                DenView(
                    profileName: profile.name,
                    profileColor: profile.color.color,
                    shouldShowHeader: !store.isZenViewPresented
                ) {
                    DenHeader(profile: profile, windowID: route.windowID)
                }

                if profileManager.openProfilePanelProfileID == activeProfileID,
                    profileManager.openProfilePanelWindowID == route.windowID
                {
                    OpenProfilePanel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 64)
                }
            }
            .tint(profile.color.color)
            .environment(store)
            .focusedSceneValue(\.denStore, store)
            .focusedSceneValue(\.profileID, activeProfileID)
            .focusedSceneValue(\.profileWindowID, route.windowID)
            .background(WindowRegistration(route: route))
            .toolbarVisibility(store.isZenViewPresented ? .hidden : .visible, for: .windowToolbar)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .ignoresSafeArea(.container, edges: store.isZenViewPresented ? .top : [])
            .onOpenURL { url in
                store.keepInDrawer(url)
            }
            .sheet(
                isPresented: Binding(
                    get: {
                        profileManager.clearBrowsingDataProfileID != nil
                            && profileManager.clearBrowsingDataWindowID == route.windowID
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
        } else {
            ContentUnavailableView("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WindowRegistration: NSViewRepresentable {
    let route: ProfileWindowRoute

    @Environment(ProfileManager.self) private var profileManager

    func makeCoordinator() -> Coordinator {
        Coordinator(route: route, profileManager: profileManager)
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
        private let route: ProfileWindowRoute
        private weak var profileManager: ProfileManager?
        private weak var window: NSWindow?
        private var closeObserver: NSObjectProtocol?

        init(route: ProfileWindowRoute, profileManager: ProfileManager) {
            self.route = route
            self.profileManager = profileManager
            super.init()
        }

        func register(_ window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            profileManager?.register(window: window, for: route)
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.unregister(window: window)
                }
            }
        }

        func unregister() {
            guard let window else {
                removeCloseObserver()
                return
            }
            unregister(window: window)
        }

        private func unregister(window: NSWindow) {
            guard self.window === window else { return }
            profileManager?.unregister(window: window, for: route)
            self.window = nil
            removeCloseObserver()
        }

        private func removeCloseObserver() {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
                self.closeObserver = nil
            }
        }
    }
}

private struct OpenProfilePanel: View {
    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                text: $query,
                prompt: Text("Search profiles")
            ) {
                Text("Open Profile")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($isFocused)

            ForEach(filteredProfiles) { profile in
                Button {
                    profileManager.openProfilePanelProfileID = nil
                    profileManager.openProfilePanelWindowID = nil
                    if !profileManager.activateWindow(for: profile.id) {
                        openWindow(value: ProfileWindowRoute(profileID: profile.id))
                    }
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
        .onExitCommand {
            profileManager.openProfilePanelProfileID = nil
            profileManager.openProfilePanelWindowID = nil
        }
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

struct ProfileWindowIDFocusedValueKey: FocusedValueKey {
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

    var profileWindowID: UUID? {
        get { self[ProfileWindowIDFocusedValueKey.self] }
        set { self[ProfileWindowIDFocusedValueKey.self] = newValue }
    }
}
