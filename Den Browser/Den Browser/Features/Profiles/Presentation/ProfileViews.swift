import AppKit
import DenDesign
import DenDomain
import DenInfrastructure
import DenPresentation
import SFSafeSymbols
import SwiftUI

struct ProfileWindowView: View {
    let route: ProfileWindowRoute
    let startUpdater: @MainActor @Sendable () -> Void
    let registerKeyboardWindow: @MainActor (NSWindow, DenWindowModel) -> Void
    let unregisterKeyboardWindow: @MainActor (NSWindow) -> Void

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
                DispatchQueue.main.async(execute: startUpdater)
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
            let controller = profileManager.controller(for: route)
        {
            ProfileDenWindow(
                route: route,
                profile: profile,
                activeProfileID: activeProfileID,
                controller: controller,
                isPrivateDen: profileManager.isPrivateDen,
                registerKeyboardWindow: registerKeyboardWindow,
                unregisterKeyboardWindow: unregisterKeyboardWindow
            )
            .id(ObjectIdentifier(controller))
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
                    ClearBrowsingDataView(
                        profile: profileManager.profile(id: id),
                        onClear: { categories in
                            _ = await profileManager.clearBrowsingData(categories: categories, profileID: id)
                        },
                        onDismiss: {
                            profileManager.clearBrowsingDataProfileID = nil
                            profileManager.clearBrowsingDataWindowID = nil
                        }
                    )
                }
            }
        } else {
            ContentUnavailableView("Profile unavailable", systemSymbol: .personCropCircleBadgeExclamationmark)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ProfileDenWindow: View {
    let route: ProfileWindowRoute
    let profile: ProfileState
    let activeProfileID: ProfileID
    let controller: DenController
    let isPrivateDen: Bool
    let registerKeyboardWindow: @MainActor (NSWindow, DenWindowModel) -> Void
    let unregisterKeyboardWindow: @MainActor (NSWindow) -> Void

    @Environment(ProfileManager.self) private var profileManager
    @State private var composition: DenWindowComposition

    private var windowModel: DenWindowModel { composition.model }

    init(
        route: ProfileWindowRoute,
        profile: ProfileState,
        activeProfileID: ProfileID,
        controller: DenController,
        isPrivateDen: Bool,
        registerKeyboardWindow: @escaping @MainActor (NSWindow, DenWindowModel) -> Void,
        unregisterKeyboardWindow: @escaping @MainActor (NSWindow) -> Void
    ) {
        self.route = route
        self.profile = profile
        self.activeProfileID = activeProfileID
        self.controller = controller
        self.isPrivateDen = isPrivateDen
        self.registerKeyboardWindow = registerKeyboardWindow
        self.unregisterKeyboardWindow = unregisterKeyboardWindow
        _composition = State(initialValue: DenWindowComposition(controller: controller))
    }

    var body: some View {
        DenView(
            profileName: profile.name,
            profileColor: profileDisplayColor(for: profile.color),
            isPrivateDen: isPrivateDen,
            shouldShowHeader: !windowModel.isZenViewPresented
        ) {
            DenHeader(profile: profile, windowID: route.windowID)
        }
        .tint(profileDisplayColor(for: profile.color))
        .focusedSceneValue(\.denController, controller)
        .focusedSceneValue(\.denWindowModel, windowModel)
        .focusedSceneValue(\.profileID, activeProfileID)
        .focusedSceneValue(\.profileWindowID, route.windowID)
        .background(
            WindowRegistration(
                route: route,
                composition: composition,
                registerKeyboardWindow: registerKeyboardWindow,
                unregisterKeyboardWindow: unregisterKeyboardWindow)
        )
        .toolbar {
            DenHeaderControls(profile: profile, windowID: route.windowID)
        }
        .environment(controller)
        .environment(windowModel)
        .toolbarVisibility(windowModel.isZenViewPresented ? .hidden : .visible, for: .windowToolbar)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: windowModel.isZenViewPresented ? .top : [])
        .onOpenURL { url in
            controller.handleExternalURL(url)
        }
        .onAppear {
            PerformanceTrace.mark("ProfileWindowView.onAppear (window content presented)", category: "Launch")
        }
    }
}

private struct WindowRegistration: NSViewRepresentable {
    let route: ProfileWindowRoute
    let composition: DenWindowComposition
    let registerKeyboardWindow: @MainActor (NSWindow, DenWindowModel) -> Void
    let unregisterKeyboardWindow: @MainActor (NSWindow) -> Void

    @Environment(ProfileManager.self) private var profileManager

    func makeCoordinator() -> Coordinator {
        Coordinator(
            route: route,
            profileManager: profileManager,
            composition: composition,
            registerKeyboardWindow: registerKeyboardWindow,
            unregisterKeyboardWindow: unregisterKeyboardWindow)
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
        private let composition: DenWindowComposition
        private let registerKeyboardWindow: @MainActor (NSWindow, DenWindowModel) -> Void
        private let unregisterKeyboardWindow: @MainActor (NSWindow) -> Void
        private weak var window: NSWindow?
        private var closeObserver: NSObjectProtocol?

        init(
            route: ProfileWindowRoute,
            profileManager: ProfileManager,
            composition: DenWindowComposition,
            registerKeyboardWindow: @escaping @MainActor (NSWindow, DenWindowModel) -> Void,
            unregisterKeyboardWindow: @escaping @MainActor (NSWindow) -> Void
        ) {
            self.route = route
            self.profileManager = profileManager
            self.composition = composition
            self.registerKeyboardWindow = registerKeyboardWindow
            self.unregisterKeyboardWindow = unregisterKeyboardWindow
            super.init()
        }

        func register(_ window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            profileManager?.register(window: window, for: route)
            composition.connect()
            registerKeyboardWindow(window, composition.model)
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
            unregisterKeyboardWindow(window)
            composition.disconnect()
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

struct OpenProfilePanel: View {
    let profiles: [ProfileState]
    let profileColor: Color
    let onOpenProfile: (ProfileID) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedProfileID: ProfileID?
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
                .denPanelHeaderField()
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
                            .fill(profileDisplayColor(for: profile.color))
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
                .denSelectionHighlight(profile.id == selectedProfileID, profileColor: profileColor)
            }
        }
        .denPanel(width: DenPanelLayout.narrowWidth)
        .onAppear { DispatchQueue.main.async { isFocused = true } }
        .onChange(of: query) { _, _ in selectedProfileID = nil }
        .onExitCommand(perform: close)
    }

    private var filteredProfiles: [ProfileState] {
        guard !query.isEmpty else { return profiles }
        return profiles.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func moveProfileSelection(by offset: Int) {
        selectedProfileID = SelectionNavigation.next(
            selectedProfileID,
            among: filteredProfiles.map(\.id),
            by: offset
        )
    }

    private func confirmSelection() {
        guard let profileID = selectedProfileID ?? filteredProfiles.first?.id else { return }
        openProfile(profileID)
    }

    private func openProfile(_ profileID: ProfileID) {
        onClose()
        onOpenProfile(profileID)
    }

    private func close() {
        onClose()
    }
}

struct DenControllerFocusedValueKey: FocusedValueKey {
    typealias Value = DenController
}

struct DenWindowModelFocusedValueKey: FocusedValueKey {
    typealias Value = DenWindowModel
}

struct ProfileIDFocusedValueKey: FocusedValueKey {
    typealias Value = ProfileID
}

struct ProfileWindowIDFocusedValueKey: FocusedValueKey {
    typealias Value = UUID
}

extension FocusedValues {
    var denController: DenController? {
        get { self[DenControllerFocusedValueKey.self] }
        set { self[DenControllerFocusedValueKey.self] = newValue }
    }

    var denWindowModel: DenWindowModel? {
        get { self[DenWindowModelFocusedValueKey.self] }
        set { self[DenWindowModelFocusedValueKey.self] = newValue }
    }

    var profileID: ProfileID? {
        get { self[ProfileIDFocusedValueKey.self] }
        set { self[ProfileIDFocusedValueKey.self] = newValue }
    }

    var profileWindowID: UUID? {
        get { self[ProfileWindowIDFocusedValueKey.self] }
        set { self[ProfileWindowIDFocusedValueKey.self] = newValue }
    }
}
