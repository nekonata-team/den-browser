import AppKit
import SFSafeSymbols
import SwiftUI

struct ProfileWindowView: View {
    let route: ProfileWindowRoute

    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content
            .handlesExternalEvents(
                preferring: appearsActive ? ["*"] : [],
                allowing: appearsActive ? [] : ["*"]
            )
            .onAppear {
                profileManager.openWindowAction = { [openWindow] targetRoute in
                    openWindow(value: targetRoute)
                }
            }
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
                store.handleExternalURL(url)
            }
            .onAppear {
                PerformanceTrace.mark("ProfileWindowView.onAppear (window content presented)", category: "Launch")
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
            ContentUnavailableView("Profile unavailable", systemSymbol: .personCropCircleBadgeExclamationmark)
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
    @State private var selectedProfileID: UUID?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .personCropCircle) {
                TextField(
                    text: $query,
                    prompt: Text("Search profiles")
                ) {
                    Text("Open Profile")
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
                .focused($isFocused)
                .accessibilityIdentifier("open-profile-input")
                .onKeyPress(.downArrow) {
                    guard !TextInputComposition.isActive else { return .ignored }
                    moveProfileSelection(by: 1)
                    return filteredProfiles.isEmpty ? .ignored : .handled
                }
                .onKeyPress(.upArrow) {
                    guard !TextInputComposition.isActive else { return .ignored }
                    moveProfileSelection(by: -1)
                    return filteredProfiles.isEmpty ? .ignored : .handled
                }
                .onSubmit {
                    TextInputComposition.performUnlessActive(confirmSelection)
                }
            }

            ForEach(filteredProfiles) { profile in
                Button {
                    openProfile(profile.id)
                } label: {
                    HStack(spacing: DenPanelLayout.controlSpacing) {
                        Circle()
                            .fill(profile.color.color)
                            .frame(width: 10, height: 10)
                        Text(profile.name)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 30)
                .background(
                    profile.id == selectedProfileID
                        ? Color.primary.opacity(0.1)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
                )
            }
        }
        .denPanel(width: 380)
        .onAppear { DispatchQueue.main.async { isFocused = true } }
        .onChange(of: query) { _, _ in selectedProfileID = nil }
        .onExitCommand(perform: close)
    }

    private var filteredProfiles: [ProfileState] {
        guard !query.isEmpty else { return profileManager.profiles }
        return profileManager.profiles.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func moveProfileSelection(by offset: Int) {
        guard !filteredProfiles.isEmpty else { return }
        let ids = filteredProfiles.map(\.id)
        let currentIndex = selectedProfileID.flatMap(ids.firstIndex(of:))
        let nextIndex: Int
        if let currentIndex {
            nextIndex = (currentIndex + offset + ids.count) % ids.count
        } else {
            nextIndex = offset > 0 ? 0 : ids.count - 1
        }
        selectedProfileID = ids[nextIndex]
    }

    private func confirmSelection() {
        guard let profileID = selectedProfileID ?? filteredProfiles.first?.id else { return }
        openProfile(profileID)
    }

    private func openProfile(_ profileID: UUID) {
        close()
        if !profileManager.activateWindow(for: profileID) {
            openWindow(value: ProfileWindowRoute(profileID: profileID))
        }
    }

    private func close() {
        profileManager.openProfilePanelProfileID = nil
        profileManager.openProfilePanelWindowID = nil
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
