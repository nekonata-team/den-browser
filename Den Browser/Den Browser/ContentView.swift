import AppKit
import SwiftUI

struct ContentView: View {
    private let boardSpacing: CGFloat = 10
    private let boardHorizontalPadding: CGFloat = 10
    private let profileName: String?
    private let profileColor: Color

    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var urlText = ""
    @State private var editBoardLinkText = ""
    @State private var newDeskLabel = ""
    @State private var selectedDeskPreset: DeskPresetSelection = .builtIn(.empty)
    @State private var activeDeskPreset: DeskPresetSelection = .builtIn(.empty)
    @State private var deskPresetQuery = ""
    @State private var isManagingDeskPresets = false
    @State private var isChoosingDeskPreset = true
    @State private var didAttemptDeskCreation = false
    @State private var saveDeskPresetLabel = ""
    @State private var saveDeskPresetMessage: String?

    @State private var didScrollToRestoredFocusedBoard = false
    @State private var resizingBoardID: UUID?
    @State private var boardFrames: [UUID: CGRect] = [:]
    @State private var pendingScroll: PendingScroll?
    @State private var boardDrag: BoardDragState?
    @State private var lastBoardAutoScrollTime = 0.0
    @State private var deskFrames: [UUID: CGRect] = [:]
    @State private var deskDrag: DeskDragState?
    @State private var lastDeskAutoScrollTime = 0.0
    @FocusState private var isOpenPanelFocused: Bool
    @FocusState private var isEditBoardLinkPanelFocused: Bool
    @FocusState private var isDeskPresetSearchFocused: Bool
    @FocusState private var isNewDeskLabelFocused: Bool
    @FocusState private var isSaveDeskPresetLabelFocused: Bool
    @State private var renameText = ""
    @FocusState private var isRenamePanelFocused: Bool

    init(profileName: String? = nil, profileColor: Color = .blue) {
        self.profileName = profileName
        self.profileColor = profileColor
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                boardStrip(in: geometry.size, safeAreaTop: geometry.safeAreaInsets.top)
                    .allowsHitTesting(
                        store.temporaryContext == nil && store.focusedDesk?.boards.isEmpty == false
                    )
                    .accessibilityHidden(
                        store.temporaryContext != nil || store.focusedDesk?.boards.isEmpty != false)

                if store.focusedDesk?.boards.isEmpty != false {
                    EmptyDenView {
                        store.showOpenBoardPanel()
                    }
                    .allowsHitTesting(store.temporaryContext == nil)
                    .accessibilityHidden(store.temporaryContext != nil)
                }

                if shouldShowDeskSwitcher {
                    deskSwitcher
                        .padding(.top, 12)
                        .allowsHitTesting(store.temporaryContext == nil)
                        .accessibilityHidden(store.temporaryContext != nil)
                }

                if store.isBoardWidthPanelPresented {
                    boardWidthPanel
                        .padding(.top, shouldShowDeskSwitcher ? 74 : 12)
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                }

                if store.isOpenBoardPanelPresented {
                    openBoardPanel(defaultBoardWidth: defaultBoardWidth(in: geometry.size))
                        .padding(.top, shouldShowDeskSwitcher ? 74 : 12)
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                }

                if store.isEditBoardLinkPanelPresented {
                    editBoardLinkPanel
                        .padding(.top, shouldShowDeskSwitcher ? 74 : 12)
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                }

                if store.isOverviewPresented {
                    OverviewView()
                        .padding(18)
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.98))
                }

                if store.isNewDeskPanelPresented {
                    newDeskPanel
                        .padding(.top, shouldShowDeskSwitcher ? 74 : 12)
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                }

                if store.isSaveDeskPresetPanelPresented {
                    saveDeskPresetPanel
                        .padding(.top, shouldShowDeskSwitcher ? 74 : 12)
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                }

                if store.isRenameBoardPanelPresented {
                    renameBoardPanel
                        .padding(.top, shouldShowDeskSwitcher ? 74 : 12)
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                }

                if store.isRenameDeskPanelPresented {
                    renameDeskPanel
                        .padding(.top, shouldShowDeskSwitcher ? 74 : 12)
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                }

                if store.isKeyboardShortcutsPresented,
                    store.focusedDesk?.boards.isEmpty == false
                {
                    KeyboardShortcutsView(onClose: store.hideKeyboardShortcuts)
                        .padding(18)
                        .frame(width: 760, height: 560)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.98))
                }
            }
            .onAppear {
                updateBoardLayout(for: geometry.size)
            }
            .onChange(of: geometry.size.width) { _, _ in
                updateBoardLayout(for: geometry.size)
            }
            .onChange(of: store.boardDragCancellationRequest) { _, _ in
                cancelBoardDrag()
            }
            .onChange(of: store.deskDragCancellationRequest) { _, _ in
                cancelDeskDrag()
            }
            .onChange(of: store.state.focusedDeskID) { _, deskID in
                if boardDrag?.deskID != deskID {
                    cancelBoardDrag()
                }
            }
            .onChange(of: store.temporaryContext) { _, context in
                if context != nil {
                    cancelBoardDrag()
                    cancelDeskDrag()
                }
            }
            .onChange(of: preferences.sheetScale) { _, scale in
                store.applySheetScale(scale)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                cancelBoardDrag()
                cancelDeskDrag()
            }
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isOpenBoardPanelPresented)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isEditBoardLinkPanelPresented)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isNewDeskPanelPresented)
            .animation(
                DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isSaveDeskPresetPanelPresented
            )
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isOverviewPresented)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isKeyboardShortcutsPresented)
            .animation(
                DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isRenameBoardPanelPresented
            )
            .animation(
                DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isRenameDeskPanelPresented
            )
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isBoardWidthPanelPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.isZenViewPresented)
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
                    .strokeBorder(.cyan.opacity(0.48), lineWidth: 1)
                    .padding(8)
                    .opacity(store.isDenMode ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isDenMode)
        }
        .background(DenBackground(isDenMode: store.isDenMode, profileColor: profileColor))
        .frame(minWidth: 1100, minHeight: 720)
        .navigationTitle(titlebarTitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("den-content")
        .accessibilityValue(store.isDenMode ? "Den Mode" : "Sheet Input")
        .confirmationDialog(
            "Delete \(store.deskPendingDeletion?.label ?? "Desk")?",
            isPresented: Binding(
                get: { store.deskPendingDeletion != nil },
                set: { if !$0 { store.cancelDeskDeletion() } })
        ) {
            Button("Delete Desk", role: .destructive) {
                store.confirmDeskDeletion()
            }
            Button("Cancel", role: .cancel) {
                store.cancelDeskDeletion()
            }
        } message: {
            let boardCount = store.deskPendingDeletion?.boards.count ?? 0
            Text(
                boardCount == 1
                    ? "Its Board and Sheet Stack will be permanently deleted."
                    : "Its \(boardCount) Boards and their Sheet Stacks will be permanently deleted."
            )
        }
        .confirmationDialog(
            "Replace \(store.deskPresetPendingReplacement?.label ?? "Desk Preset")?",
            isPresented: Binding(
                get: { store.deskPresetPendingReplacement != nil },
                set: { if !$0 { store.cancelDeskPresetReplacement() } })
        ) {
            Button("Replace Preset") {
                store.confirmDeskPresetReplacement()
                store.hideSaveDeskPresetPanel()
            }
            Button("Cancel", role: .cancel) { store.cancelDeskPresetReplacement() }
        } message: {
            Text("Existing Desks will not be affected.")
        }
        .confirmationDialog(
            "Delete \(store.deskPresetPendingDeletion?.label ?? "Desk Preset")?",
            isPresented: Binding(
                get: { store.deskPresetPendingDeletion != nil },
                set: { if !$0 { store.cancelDeskPresetDeletion() } })
        ) {
            Button("Delete Preset", role: .destructive) { confirmDeskPresetDeletion() }
            Button("Cancel", role: .cancel) { store.cancelDeskPresetDeletion() }
        } message: {
            Text("Existing Desks will not be affected.")
        }
    }

    private var titlebarTitle: String {
        let profilePrefix = profileName.map { "\($0) · " } ?? ""
        guard store.isDenMode else { return profileName.map { "\($0) — Den Browser" } ?? "Den Browser" }
        return profilePrefix + "DEN MODE"
    }

    private var deskSwitcher: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(store.state.desks) { desk in
                                deskSwitcherItem(desk, in: geometry.size, using: proxy)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.state.desks.map(\.id))
                }
                .coordinateSpace(name: DeskSwitcherCoordinateSpace.name)
                .scrollIndicators(.hidden)
                .onChange(of: store.state.focusedDeskID) { _, deskID in
                    withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                        proxy.scrollTo(deskID, anchor: .center)
                    }
                }
                .onPreferenceChange(DeskFramePreferenceKey.self) { frames in
                    deskFrames = frames
                    alignDraggedDesk(to: frames)
                }
            }
            .frame(height: 36)
        }
    }

    @ViewBuilder
    private func deskSwitcherButton(_ desk: DeskState, in size: CGSize, using proxy: ScrollViewProxy) -> some View {
        deskButton(desk, in: size, using: proxy)
            .id(desk.id)
    }

    private func deskSwitcherItem(_ desk: DeskState, in size: CGSize, using proxy: ScrollViewProxy) -> some View {
        let isDragged = deskDrag?.deskID == desk.id
        let offset = isDragged ? deskDrag?.offset ?? 0 : 0
        return deskSwitcherButton(desk, in: size, using: proxy)
            .offset(x: offset)
            .background(deskFrameBackground(for: desk.id))
            .zIndex(isDragged ? 2 : 1)
    }

    private func deskButton(_ desk: DeskState, in size: CGSize, using proxy: ScrollViewProxy) -> some View {
        Text(desk.label)
            .lineLimit(1)
            .frame(maxWidth: 180)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                if desk.id == store.state.focusedDeskID {
                    Capsule().fill(profileColor.opacity(0.35))
                }
            }
            .glassEffect(.regular, in: Capsule())
            .contentShape(.capsule)
            .contextMenu {
                Button {
                    store.focusDesk(desk.id)
                    store.showRenameDeskPanel()
                } label: {
                    Label("Rename Desk", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.focusDesk(desk.id)
                    store.deleteFocusedDesk()
                } label: {
                    Label("Delete Desk", systemImage: "trash")
                }
                .disabled(!store.canDeleteFocusedDesk)

                Divider()

                Button {
                    store.focusDesk(desk.id)
                    store.showSaveDeskPresetPanel()
                } label: {
                    Label("Save Desk as Preset...", systemImage: "square.and.arrow.down")
                }
                .disabled(desk.boards.isEmpty)

                Button {
                    store.showDeskPresetManagement()
                } label: {
                    Label("Manage Presets...", systemImage: "slider.horizontal.3")
                }

                Divider()

                Button {
                    store.showNewDeskPanel()
                } label: {
                    Label("New Desk...", systemImage: "plus")
                }
                .disabled(!store.canCreateDesk)
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(DeskSwitcherCoordinateSpace.name))
                    .onChanged { updateDeskDrag(desk, value: $0, in: size, using: proxy) }
                    .onEnded { finishDeskGesture(desk, value: $0, in: size) }
            )
            .allowsHitTesting(!store.isDeskDragging || deskDrag?.deskID == desk.id)
            .help("Drag to reorder Desk")
            .accessibilityHint("Drag to reorder this Desk")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { store.focusDesk(desk.id) }
            .accessibilityIdentifier("desk-switcher.\(desk.id.uuidString.lowercased())")
    }

    private func deskFrameBackground(for deskID: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: DeskFramePreferenceKey.self,
                value: [deskID: proxy.frame(in: .named(DeskSwitcherCoordinateSpace.name))]
            )
        }
    }

    private var newDeskPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(
                    systemName: store.isDeskPresetManagementPresented
                        ? "bookmark" : "rectangle.stack.badge.plus"
                )
                .foregroundStyle(.secondary)
                Text(store.isDeskPresetManagementPresented ? "Manage Presets" : "New Desk")
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(height: 38)

            if isChoosingDeskPreset {
                DeskPresetPicker(
                    selection: $activeDeskPreset,
                    query: $deskPresetQuery,
                    isManaging: $isManagingDeskPresets,
                    isSearchFocused: $isDeskPresetSearchFocused,
                    onConfirm: confirmDeskPreset)
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deskPresetLabel(for: selectedDeskPreset))
                            .font(.headline)
                        Text(boardCountLabel(selectedDeskPresetBoards.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change Preset") { beginDeskPresetSelection() }
                        .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous)
                )

                DeskPresetPreview(boards: selectedDeskPresetBoards)

                TextField("Desk label", text: $newDeskLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16, weight: .medium))
                    .focused($isNewDeskLabelFocused)
                    .onSubmit(createDesk)
                    .onKeyPress(phases: .down) { keyPress in
                        let isBackTab = keyPress.key == .tab || keyPress.characters == "\u{19}"
                        guard isBackTab, keyPress.modifiers.contains(.shift) else {
                            return .ignored
                        }
                        beginDeskPresetSelection()
                        return .handled
                    }

                HStack(spacing: 12) {
                    if didAttemptDeskCreation && trimmedNewDeskLabel.isEmpty {
                        Text("Enter a desk label")
                            .foregroundStyle(.red)
                    } else {
                        Text(newDeskPanelDescription)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Create", action: createDesk)
                        .buttonStyle(.glassProminent)
                        .disabled(trimmedNewDeskLabel.isEmpty || !store.canCreateDesk)
                }
                .font(.system(size: 12))
            }
        }
        .padding(16)
        .frame(width: 620)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            selectedDeskPreset = .builtIn(.empty)
            activeDeskPreset = .builtIn(.empty)
            newDeskLabel = BuiltInDeskPreset.empty.label
            deskPresetQuery = ""
            isManagingDeskPresets = store.isDeskPresetManagementPresented
            isChoosingDeskPreset = true
            didAttemptDeskCreation = false
            DispatchQueue.main.async {
                isDeskPresetSearchFocused = true
            }
        }
        .onExitCommand {
            if isChoosingDeskPreset {
                store.hideNewDeskPanel()
            } else {
                beginDeskPresetSelection()
            }
        }
    }

    private var saveDeskPresetPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .foregroundStyle(.secondary)
                Text("Save Desk as Preset")
                    .font(.system(size: 17, weight: .semibold))
            }

            TextField("Preset label", text: $saveDeskPresetLabel)
                .textFieldStyle(.roundedBorder)
                .focused($isSaveDeskPresetLabelFocused)
                .onSubmit(saveDeskPreset)

            DeskPresetPreview(
                boards: store.focusedDesk?.boards.map(DeskPresetBoard.init) ?? [])

            HStack {
                Text(saveDeskPresetMessage ?? "Captures the current Board arrangement")
                    .font(.caption)
                    .foregroundStyle(saveDeskPresetMessage == nil ? Color.secondary : Color.red)
                Spacer()
                Button("Save Preset", action: saveDeskPreset)
                    .buttonStyle(.glassProminent)
                    .disabled(saveDeskPresetLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            saveDeskPresetLabel = store.focusedDesk?.label ?? ""
            saveDeskPresetMessage = nil
            DispatchQueue.main.async { isSaveDeskPresetLabelFocused = true }
        }
        .onExitCommand { store.hideSaveDeskPresetPanel() }
    }

    private var trimmedNewDeskLabel: String {
        newDeskLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var newDeskPanelDescription: String {
        store.canCreateDesk ? "New desk opens after the focused desk" : "A Den can contain up to 10 desks"
    }

    private func createDesk() {
        didAttemptDeskCreation = true
        guard !trimmedNewDeskLabel.isEmpty else { return }
        switch selectedDeskPreset {
        case .builtIn(let preset):
            store.createDesk(label: newDeskLabel, preset: preset)
        case .personal(let id):
            store.createDesk(label: newDeskLabel, personalPresetID: id)
        }
        newDeskLabel = ""
        selectedDeskPreset = .builtIn(.empty)
        didAttemptDeskCreation = false
    }

    private func confirmDeskPreset(_ selection: DeskPresetSelection) {
        activeDeskPreset = selection
        selectedDeskPreset = selection
        newDeskLabel = deskPresetLabel(for: selection)
        isChoosingDeskPreset = false
        didAttemptDeskCreation = false
        DispatchQueue.main.async {
            isNewDeskLabelFocused = true
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    private func beginDeskPresetSelection() {
        activeDeskPreset = selectedDeskPreset
        isChoosingDeskPreset = true
        isManagingDeskPresets = false
        DispatchQueue.main.async { isDeskPresetSearchFocused = true }
    }

    private func deskPresetLabel(for selection: DeskPresetSelection) -> String {
        switch selection {
        case .builtIn(let preset):
            preset.label
        case .personal(let id):
            store.deskPresets.first(where: { $0.id == id })?.label ?? BuiltInDeskPreset.empty.label
        }
    }

    private var selectedDeskPresetBoards: [DeskPresetBoard] {
        switch selectedDeskPreset {
        case .builtIn(let preset):
            preset.boards
        case .personal(let id):
            store.deskPresets.first(where: { $0.id == id })?.boards ?? []
        }
    }

    private func boardCountLabel(_ count: Int) -> String {
        count == 1 ? "1 Board" : "\(count) Boards"
    }

    private func saveDeskPreset() {
        switch store.saveFocusedDeskAsPreset(label: saveDeskPresetLabel) {
        case .created:
            store.hideSaveDeskPresetPanel()
        case .replacementPending:
            saveDeskPresetMessage = nil
        case .invalidLabel:
            saveDeskPresetMessage = "Enter a Preset label"
        case .emptyDesk:
            saveDeskPresetMessage = "A Personal Desk Preset needs at least one Board"
        case .reservedLabel:
            saveDeskPresetMessage = "Built-in Desk Preset labels are reserved"
        }
    }

    private func confirmDeskPresetDeletion() {
        if case .personal(let id) = selectedDeskPreset,
            let pending = store.deskPresetPendingDeletion,
            pending.id == id
        {
            if newDeskLabel == pending.label {
                newDeskLabel = BuiltInDeskPreset.empty.label
            }
            selectedDeskPreset = .builtIn(.empty)
        }
        store.confirmDeskPresetDeletion()
    }

    private var shouldShowDeskSwitcher: Bool {
        !store.isZenViewPresented
    }

    private func defaultBoardWidth(in size: CGSize) -> Double {
        if let focusedBoard = store.focusedBoard {
            return focusedBoard.width
        }
        return (size.width - boardHorizontalPadding * 2 - boardSpacing) / 2
    }

    private func openBoardPanel(defaultBoardWidth: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .foregroundStyle(.secondary)

                TextField("Open URL or search", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isOpenPanelFocused)
                    .onSubmit {
                        openBoard(defaultBoardWidth: defaultBoardWidth)
                    }
            }
            .frame(height: 38)

            HStack(spacing: 12) {
                Text("New board opens to the right of the focused board")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("n in Den Mode")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            DispatchQueue.main.async {
                isOpenPanelFocused = true
            }
        }
        .onExitCommand {
            store.hideOpenBoardPanel()
        }
    }

    private var editBoardLinkPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)

                TextField("Open URL or search", text: $editBoardLinkText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isEditBoardLinkPanelFocused)
                    .onSubmit {
                        editFocusedBoardLink()
                    }
            }
            .frame(height: 38)

            HStack(spacing: 12) {
                Text("Replace the Current Sheet in the focused Board")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘L")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            editBoardLinkText = store.focusedBoard?.currentSheetURL?.absoluteString ?? ""
            DispatchQueue.main.async {
                isEditBoardLinkPanelFocused = true
            }
        }
        .onExitCommand {
            store.hideEditBoardLinkPanel()
        }
    }

    private var renameBoardPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)

                TextField("Rename board", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isRenamePanelFocused)
                    .onSubmit {
                        store.renameFocusedBoard(to: renameText)
                    }
            }
            .frame(height: 38)

            HStack(spacing: 12) {
                Text("Leave empty to restore page-provided title")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("r in Den Mode")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            if let desk = store.focusedDesk,
                let focusedBoardID = desk.focusedBoardID,
                let board = desk.boards.first(where: { $0.id == focusedBoardID })
            {
                renameText = board.customLabel ?? board.label
            } else {
                renameText = ""
            }
            DispatchQueue.main.async {
                isRenamePanelFocused = true
            }
        }
        .onExitCommand {
            store.hideRenameBoardPanel()
        }
    }

    private var renameDeskPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)

                TextField("Rename desk", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isRenamePanelFocused)
                    .onSubmit {
                        store.renameFocusedDesk(to: renameText)
                    }
            }
            .frame(height: 38)

            HStack(spacing: 12) {
                Text("Press Return to confirm, Escape to cancel")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("R in Den Mode")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            if let desk = store.focusedDesk {
                renameText = desk.label
            } else {
                renameText = ""
            }
            DispatchQueue.main.async {
                isRenamePanelFocused = true
            }
        }
        .onExitCommand {
            store.hideRenameDeskPanel()
        }
    }

    private var boardWidthPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Resize Boards to Fit")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: store.hideBoardWidthPanel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Close Board Width")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(1...9, id: \.self) { count in
                    let width = store.boardWidth(toFit: count)
                    Button {
                        store.resizeFocusedDeskBoards(toFit: count)
                    } label: {
                        VStack(spacing: 2) {
                            Text(count == 1 ? "1 Board" : "\(count) Boards")
                            Text(width.map { "\(Int($0.rounded())) pt" } ?? "Unavailable")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(!store.canResizeFocusedDeskBoards(toFit: count))
                    .accessibilityHint("Applies to every Board in the Focused Desk")
                }
            }

            Text(
                store.boardWidthPanelMessage
                    ?? "Changes every Board in the Focused Desk. Press - / = or 1–9, then Escape."
            )
            .font(.system(size: 12))
            .foregroundStyle(store.boardWidthPanelMessage == nil ? Color.secondary : Color.red)
        }
        .padding(16)
        .frame(width: 420)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onExitCommand {
            store.hideBoardWidthPanel()
        }
    }

    private func boardStrip(in size: CGSize, safeAreaTop: CGFloat) -> some View {
        let boards = store.focusedDesk?.boards ?? []
        let topInset: CGFloat = shouldShowDeskSwitcher ? 48 : 10
        let bottomInset: CGFloat = 10
        let boardHeight = max(420, size.height - topInset - bottomInset)
        let maximizedBoardWidth = max(280, size.width - boardHorizontalPadding * 2)
        let layoutParams = BoardLayout.Parameters(
            centering: preferences.boardCentering,
            boards: boards,
            maximizedBoardID: store.maximizedBoardID,
            windowWidth: size.width,
            horizontalPadding: boardHorizontalPadding,
            spacing: boardSpacing
        )
        let paddings = BoardLayout.calculatePaddings(for: layoutParams)
        let leadingPadding = paddings.leading
        let trailingPadding = paddings.trailing
        return ScrollViewReader { scrollProxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: boardSpacing) {
                    ForEach(boards) { board in
                        BoardView(
                            board: board,
                            isFocused: board.id == store.focusedDesk?.focusedBoardID,
                            isDragging: boardDrag?.boardID == board.id,
                            runtime: store.runtime(for: board),
                            width: store.maximizedBoardID == board.id ? maximizedBoardWidth : board.width,
                            height: boardHeight,
                            isPointerFocusEnabled: isBoardPointerFocusEnabled(for: board.id),
                            onFocus: { store.focusBoard(board.id) },
                            onGoBack: { store.goBackInBoard(board.id) },
                            onGoForward: { store.goForwardInBoard(board.id) },
                            onRemove: { store.removeBoard(board.id) },
                            onDragChanged: {
                                updateBoardDrag(board, value: $0, in: size, using: scrollProxy)
                            },
                            onDragEnded: { finishBoardDrag(value: $0, in: size) }
                        )
                        .id(board.id)
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.98))
                        .offset(
                            x: boardDrag?.boardID == board.id ? boardDrag?.offset.width ?? 0 : 0,
                            y: boardDrag?.boardID == board.id ? boardDrag?.offset.height ?? 0 : 0
                        )
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: BoardFramePreferenceKey.self,
                                    value: [board.id: proxy.frame(in: .named(BoardStripCoordinateSpace.name))]
                                )
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if store.maximizedBoardID != board.id {
                                BoardResizeHandle(
                                    board: board,
                                    height: boardHeight,
                                    width: boardSpacing,
                                    onResizeStart: {
                                        resizingBoardID = board.id
                                        store.focusBoard(board.id)
                                    },
                                    onResize: { store.resizeBoard(board.id, to: $0) },
                                    onResizeEnd: {
                                        store.saveBoardWidths()
                                        resizingBoardID = nil
                                    }
                                )
                                .offset(x: boardSpacing)
                            }
                        }
                        .allowsHitTesting(isBoardPointerFocusEnabled(for: board.id))
                        .accessibilityHidden(!isBoardPointerFocusEnabled(for: board.id))
                        .zIndex(boardDrag?.boardID == board.id ? 2 : 1)
                    }
                }
                .padding(.leading, leadingPadding)
                .padding(.trailing, trailingPadding)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
                .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: boards.map(\.id))
                .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: boards.map(\.width))
                .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.maximizedBoardID)
            }
            .coordinateSpace(name: BoardStripCoordinateSpace.name)
            .scrollIndicators(.never)
            .accessibilityIdentifier("board-strip")
            .onPreferenceChange(BoardFramePreferenceKey.self) { frames in
                boardFrames = frames
                alignDraggedBoard(to: frames)

                if let pending = pendingScroll, frames[pending.boardID] != nil {
                    // Ensure the updated padding layout is applied before scrolling.
                    if let firstBoardID = boards.first?.id, let firstFrame = frames[firstBoardID] {
                        let expectedMinX = leadingPadding
                        let actualMinX = firstFrame.minX
                        if abs(actualMinX - expectedMinX) > 2.0 {
                            return  // Wait until layout changes are committed
                        }
                    }
                    pendingScroll = nil
                    centerBoard(pending.boardID, using: scrollProxy, animated: pending.animated)
                }
            }
            .onAppear {
                guard !didScrollToRestoredFocusedBoard else { return }
                didScrollToRestoredFocusedBoard = true
                if let boardID = store.focusedDesk?.focusedBoardID {
                    if boardFrames[boardID] != nil {
                        centerBoard(boardID, using: scrollProxy, animated: false)
                    } else {
                        pendingScroll = PendingScroll(boardID: boardID, animated: false)
                    }
                }
            }
            .onChange(of: boardFocusTarget) { previous, current in
                guard let boardID = current.boardID else { return }
                if boardFrames[boardID] != nil {
                    centerBoard(
                        boardID,
                        using: scrollProxy,
                        animated: previous.deskID == current.deskID
                    )
                } else {
                    pendingScroll = PendingScroll(boardID: boardID, animated: previous.deskID == current.deskID)
                }
            }
            .onChange(of: store.centerFocusedBoardRequest) { _, _ in
                centerBoard(store.focusedDesk?.focusedBoardID, using: scrollProxy)
            }
        }
    }

    private func centerBoard(_ boardID: UUID?, using proxy: ScrollViewProxy, animated: Bool = true) {
        guard resizingBoardID == nil, !store.isBoardDragging, let boardID else { return }

        Task { @MainActor in
            // Sleep briefly to allow SwiftUI layout updates and content size changes to settle
            try? await Task.sleep(for: .milliseconds(100))
            if animated {
                withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                    proxy.scrollTo(boardID, anchor: .center)
                }
            } else {
                proxy.scrollTo(boardID, anchor: .center)
            }
        }
    }

    private var boardFocusTarget: BoardFocusTarget {
        BoardFocusTarget(
            deskID: store.state.focusedDeskID,
            boardID: store.focusedDesk?.focusedBoardID)
    }

    private func isBoardPointerFocusEnabled(for boardID: UUID) -> Bool {
        (!store.isBoardDragging || boardDrag?.boardID == boardID)
            && store.temporaryContext == nil
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    private func openBoard(defaultBoardWidth: Double) {
        store.addBoard(urlString: urlText, preferredWidth: defaultBoardWidth)
        urlText = ""
    }

    private func editFocusedBoardLink() {
        if store.navigateFocusedBoard(urlString: editBoardLinkText) {
            editBoardLinkText = ""
        }
    }

    private func updateDeskDrag(
        _ desk: DeskState,
        value: DragGesture.Value,
        in size: CGSize,
        using scrollProxy: ScrollViewProxy
    ) {
        if deskDrag == nil {
            guard deskDragDistance(value.translation) >= 4 else { return }
            guard let frame = deskFrames[desk.id], store.beginDeskDrag(desk.id) else { return }
            deskDrag = DeskDragState(
                deskID: desk.id,
                originalOrder: store.state.desks.map(\.id),
                startCenterX: frame.midX
            )
        }

        guard var drag = deskDrag, drag.deskID == desk.id else { return }
        drag.translation = value.translation
        if let frame = deskFrames[desk.id] {
            drag.offset = drag.desiredCenterX - frame.midX
        }
        deskDrag = drag
        updateDeskInsertion()
        autoScrollDeskSwitcher(at: value.location, in: size, using: scrollProxy)
    }

    private func finishDeskGesture(_ desk: DeskState, value: DragGesture.Value, in size: CGSize) {
        if deskDrag?.deskID == desk.id {
            finishDeskDrag(value: value, in: size)
        } else if deskDragDistance(value.translation) < 4 {
            store.focusDesk(desk.id)
        }
    }

    private func deskDragDistance(_ translation: CGSize) -> CGFloat {
        hypot(translation.width, translation.height)
    }

    private func updateDeskInsertion() {
        guard var drag = deskDrag else { return }

        while let index = store.state.desks.firstIndex(where: { $0.id == drag.deskID }),
            let targetIndex = DeskDragInsertion.targetIndex(
                draggedDeskID: drag.deskID,
                orderedDeskIDs: store.state.desks.map(\.id),
                desiredCenterX: drag.desiredCenterX,
                frames: deskFrames)
        {
            let crossedDesk = store.state.desks[targetIndex]
            store.previewDeskMove(drag.deskID, to: targetIndex)
            let direction = targetIndex > index ? -1.0 : 1.0
            drag.offset += direction * (crossedDeskFrameWidth(crossedDesk.id) + 8)
            deskDrag = drag
        }
    }

    private func crossedDeskFrameWidth(_ deskID: UUID) -> CGFloat {
        deskFrames[deskID]?.width ?? 0
    }

    private func alignDraggedDesk(to frames: [UUID: CGRect]) {
        guard var drag = deskDrag, let frame = frames[drag.deskID] else { return }
        let offset = drag.desiredCenterX - frame.midX
        guard abs(offset - drag.offset) > 0.5 else { return }
        drag.offset = offset
        deskDrag = drag
    }

    private func autoScrollDeskSwitcher(
        at location: CGPoint,
        in size: CGSize,
        using scrollProxy: ScrollViewProxy
    ) {
        guard
            location.y >= 0,
            location.y <= size.height,
            let drag = deskDrag,
            let index = store.state.desks.firstIndex(where: { $0.id == drag.deskID })
        else { return }

        let desks = store.state.desks
        let edge: CGFloat = 40
        let targetID: UUID?
        let distanceToEdge: CGFloat
        if location.x < edge, index > 0 {
            targetID = desks[index - 1].id
            distanceToEdge = max(0, location.x)
        } else if location.x > size.width - edge, index < desks.count - 1 {
            targetID = desks[index + 1].id
            distanceToEdge = max(0, size.width - location.x)
        } else {
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let interval = distanceToEdge < 16 ? 0.06 : 0.16
        guard now - lastDeskAutoScrollTime >= interval, let targetID else { return }
        lastDeskAutoScrollTime = now
        withAnimation(.linear(duration: shouldReduceMotion ? 0 : 0.14)) {
            scrollProxy.scrollTo(targetID, anchor: .center)
        }
    }

    private func finishDeskDrag(value: DragGesture.Value, in size: CGSize) {
        guard let drag = deskDrag else { return }
        let isInside =
            value.location.x >= 0 && value.location.x <= size.width
            && value.location.y >= 0 && value.location.y <= size.height
        if isInside {
            store.finishDeskDrag()
            deskDrag = nil
        } else {
            cancelDeskDrag(drag)
        }
    }

    private func cancelDeskDrag(_ drag: DeskDragState? = nil) {
        guard let drag = drag ?? deskDrag else { return }
        let restore = {
            store.restoreDeskOrder(drag.originalOrder)
            store.finishDeskDrag()
            deskDrag = nil
        }
        if shouldReduceMotion {
            restore()
        } else {
            withAnimation(DenMotion.spatial(reduceMotion: false)) {
                restore()
            }
        }
    }

    private func updateBoardLayout(for size: CGSize) {
        store.updateBoardLayout(
            availableWidth: size.width - boardHorizontalPadding * 2,
            spacing: boardSpacing
        )
    }

    private func updateBoardDrag(
        _ board: BoardState,
        value: DragGesture.Value,
        in size: CGSize,
        using scrollProxy: ScrollViewProxy
    ) {
        if boardDrag == nil {
            guard
                let desk = store.focusedDesk,
                let frame = boardFrames[board.id],
                store.beginBoardDrag(board.id)
            else { return }
            boardDrag = BoardDragState(
                boardID: board.id,
                deskID: desk.id,
                originalOrder: desk.boards.map(\.id),
                startCenterX: frame.midX
            )
        }

        guard var drag = boardDrag, drag.boardID == board.id else { return }
        drag.translation = value.translation
        drag.offset.height = value.translation.height
        if let frame = boardFrames[board.id] {
            drag.offset.width = drag.desiredCenterX - frame.midX
        }
        boardDrag = drag
        updateBoardInsertion()
        autoScrollBoardStrip(at: value.location, in: size, using: scrollProxy)
    }

    private func updateBoardInsertion() {
        guard var drag = boardDrag, store.focusedDesk?.id == drag.deskID else { return }

        while let boards = store.focusedDesk?.boards,
            let index = deskIndex(of: drag.boardID),
            let targetIndex = BoardDragInsertion.targetIndex(
                draggedBoardID: drag.boardID,
                orderedBoardIDs: boards.map(\.id),
                desiredCenterX: drag.desiredCenterX,
                frames: boardFrames)
        {
            let crossedBoard = boards[targetIndex]
            store.previewBoardMove(drag.boardID, to: targetIndex)
            let direction = targetIndex > index ? -1.0 : 1.0
            drag.offset.width += direction * (crossedBoard.width + boardSpacing)
            boardDrag = drag
        }
    }

    private func deskIndex(of boardID: UUID) -> Int? {
        store.focusedDesk?.boards.firstIndex { $0.id == boardID }
    }

    private func alignDraggedBoard(to frames: [UUID: CGRect]) {
        guard var drag = boardDrag, let frame = frames[drag.boardID] else { return }
        let offsetX = drag.desiredCenterX - frame.midX
        guard abs(offsetX - drag.offset.width) > 0.5 else { return }
        drag.offset.width = offsetX
        boardDrag = drag
    }

    private func autoScrollBoardStrip(
        at location: CGPoint,
        in size: CGSize,
        using scrollProxy: ScrollViewProxy
    ) {
        guard
            location.y >= 0,
            location.y <= size.height,
            let drag = boardDrag,
            let index = deskIndex(of: drag.boardID),
            let boards = store.focusedDesk?.boards
        else { return }

        let edge: CGFloat = 48
        let targetID: UUID?
        let distanceToEdge: CGFloat
        if location.x < edge, index > 0 {
            targetID = boards[index - 1].id
            distanceToEdge = max(0, location.x)
        } else if location.x > size.width - edge, index < boards.count - 1 {
            targetID = boards[index + 1].id
            distanceToEdge = max(0, size.width - location.x)
        } else {
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let interval = distanceToEdge < 16 ? 0.06 : 0.16
        guard now - lastBoardAutoScrollTime >= interval, let targetID else { return }
        lastBoardAutoScrollTime = now
        withAnimation(.linear(duration: shouldReduceMotion ? 0 : 0.14)) {
            scrollProxy.scrollTo(targetID, anchor: .center)
        }
    }

    private func finishBoardDrag(value: DragGesture.Value, in size: CGSize) {
        guard let drag = boardDrag else { return }
        let isInside =
            value.location.x >= 0 && value.location.x <= size.width
            && value.location.y >= 0 && value.location.y <= size.height
        if isInside {
            store.finishBoardDrag()
            boardDrag = nil
        } else {
            cancelBoardDrag(drag)
        }
        NSCursor.arrow.set()
    }

    private func cancelBoardDrag(_ drag: BoardDragState? = nil) {
        guard let drag = drag ?? boardDrag else { return }
        let restore = {
            store.restoreBoardOrder(drag.originalOrder, in: drag.deskID)
            store.finishBoardDrag()
            boardDrag = nil
        }
        if shouldReduceMotion {
            restore()
        } else {
            withAnimation(DenMotion.spatial(reduceMotion: false)) {
                restore()
            }
        }
        NSCursor.arrow.set()
    }
}

private struct PendingScroll {
    let boardID: UUID
    let animated: Bool
}

private struct BoardFocusTarget: Equatable {
    let deskID: UUID?
    let boardID: UUID?
}

private enum DeskSwitcherCoordinateSpace {
    static let name = "desk-switcher"
}

private struct DeskDragState {
    let deskID: UUID
    let originalOrder: [UUID]
    let startCenterX: CGFloat
    var translation: CGSize = .zero
    var offset: CGFloat = 0

    var desiredCenterX: CGFloat {
        startCenterX + translation.width
    }
}

enum DeskDragInsertion {
    static func targetIndex(
        draggedDeskID: UUID,
        orderedDeskIDs: [UUID],
        desiredCenterX: CGFloat,
        frames: [UUID: CGRect]
    ) -> Int? {
        guard let index = orderedDeskIDs.firstIndex(of: draggedDeskID) else { return nil }

        if orderedDeskIDs.indices.contains(index + 1),
            let nextFrame = frames[orderedDeskIDs[index + 1]],
            desiredCenterX > nextFrame.midX
        {
            return index + 1
        }
        if orderedDeskIDs.indices.contains(index - 1),
            let previousFrame = frames[orderedDeskIDs[index - 1]],
            desiredCenterX < previousFrame.midX
        {
            return index - 1
        }
        return nil
    }
}

private struct DeskFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum BoardDragInsertion {
    static func targetIndex(
        draggedBoardID: UUID,
        orderedBoardIDs: [UUID],
        desiredCenterX: CGFloat,
        frames: [UUID: CGRect]
    ) -> Int? {
        guard let index = orderedBoardIDs.firstIndex(of: draggedBoardID) else { return nil }

        if orderedBoardIDs.indices.contains(index + 1),
            let nextFrame = frames[orderedBoardIDs[index + 1]],
            desiredCenterX > nextFrame.midX
        {
            return index + 1
        }
        if orderedBoardIDs.indices.contains(index - 1),
            let previousFrame = frames[orderedBoardIDs[index - 1]],
            desiredCenterX < previousFrame.midX
        {
            return index - 1
        }
        return nil
    }
}

private struct BoardDragState {
    let boardID: UUID
    let deskID: UUID
    let originalOrder: [UUID]
    let startCenterX: CGFloat
    var translation: CGSize = .zero
    var offset: CGSize = .zero

    var desiredCenterX: CGFloat {
        startCenterX + translation.width
    }
}

private struct BoardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct BoardResizeHandle: View {
    @State private var isHovering = false
    @State private var widthAtDragStart: Double?

    let board: BoardState
    let height: Double
    let width: Double
    let onResizeStart: () -> Void
    let onResize: (Double) -> Void
    let onResizeEnd: () -> Void

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(Color.primary.opacity(0.38))
                    .frame(width: 2, height: 34)
                    .opacity(isHovering || widthAtDragStart != nil ? 1 : 0)
            }
            .onHover { isHovering in
                self.isHovering = isHovering
                (isHovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if widthAtDragStart == nil {
                            widthAtDragStart = board.width
                            onResizeStart()
                        }
                        onResize((widthAtDragStart ?? board.width) + value.translation.width)
                    }
                    .onEnded { _ in
                        widthAtDragStart = nil
                        onResizeEnd()
                    }
            )
            .help("Drag to resize board")
            .accessibilityLabel("Resize \(board.displayName) board")
    }
}

#Preview {
    ContentView()
        .environment(DenStore())
        .environment(AppPreferences())
}

private struct DenBackground: View {
    let isDenMode: Bool
    let profileColor: Color

    var body: some View {
        LinearGradient(
            colors: isDenMode
                ? [
                    Color(red: 0.03, green: 0.18, blue: 0.23),
                    Color(red: 0.06, green: 0.10, blue: 0.18),
                ]
                : [
                    Color(red: 0.08, green: 0.10, blue: 0.12),
                    Color(red: 0.15, green: 0.16, blue: 0.19),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(.cyan.opacity(isDenMode ? 0.22 : 0.12))
                .blur(radius: 120)
                .frame(width: 420, height: 280)
                .offset(x: -120, y: -80)
        }
        .overlay(alignment: .topTrailing) {
            Rectangle()
                .fill(profileColor.opacity(isDenMode ? 0.05 : 0.10))
                .blur(radius: 140)
                .frame(width: 420, height: 280)
                .offset(x: 140, y: -90)
        }
        .ignoresSafeArea()
    }
}

private struct EmptyDenView: View {
    let openBoard: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Den Browser")
                    .font(.system(size: 28, weight: .semibold))

                Text("Open a board to start arranging web work.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            KeyboardShortcutsView()
                .padding(18)
                .frame(width: 760, height: 460)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))

            Button("Open Board", action: openBoard)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}

private struct OverviewView: View {
    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 12) {
                Text("Overview")
                    .font(.system(size: 20, weight: .bold))

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(store.isOverviewFilterMode ? .primary : .secondary)

                    TextField(
                        "Search desks and boards (/)",
                        text: Binding(
                            get: {
                                store.overviewQuery
                            },
                            set: { newValue in
                                store.setOverviewQuery(newValue)
                            }
                        )
                    )
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .disabled(!store.isOverviewFilterMode)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 320)
                .background(
                    Color.primary.opacity(store.isOverviewFilterMode ? 0.08 : 0.04),
                    in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                        .stroke(
                            store.isOverviewFilterMode ? .cyan.opacity(0.86) : Color.primary.opacity(0.10),
                            lineWidth: store.isOverviewFilterMode ? 1.5 : 1
                        )
                }
                .onTapGesture {
                    if !store.isOverviewFilterMode {
                        store.enterOverviewFilterMode()
                    }
                }
            }
            .frame(maxWidth: .infinity)

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(store.state.desks) { desk in
                        let filtered = desk.boards.filter { board in
                            store.matchesOverviewFilter(board, in: desk)
                        }
                        if store.overviewQuery.isEmpty {
                            deskRow(desk, filteredBoards: filtered)
                        } else if !filtered.isEmpty {
                            deskRow(desk, filteredBoards: filtered)
                        }
                    }
                }
                .padding(2)
                .animation(
                    DenMotion.spatial(reduceMotion: shouldReduceMotion),
                    value: store.state.desks.map { $0.boards.map(\.id) })
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                store.hideOverview()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glass)
            .padding(14)
        }
        .onExitCommand {
            store.hideOverview()
        }
        .onChange(of: store.isOverviewFilterMode) { _, newValue in
            isSearchFocused = newValue
        }
    }

    private func deskRow(_ desk: DeskState, filteredBoards: [BoardState]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(desk.label)
                    .font(.system(size: 13, weight: .semibold))

                if desk.id == store.overviewSelectionDeskID {
                    Circle()
                        .fill(.cyan)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundStyle(Color.primary.opacity(desk.id == store.overviewSelectionDeskID ? 0.96 : 0.58))

            HStack(alignment: .top, spacing: 10) {
                if filteredBoards.isEmpty {
                    Text("Empty")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 150, height: 88)
                        .background(
                            Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous))
                } else {
                    ForEach(filteredBoards) { board in
                        overviewBoard(board, in: desk)
                    }
                }
            }
        }
    }

    private func overviewBoard(_ board: BoardState, in desk: DeskState) -> some View {
        let isSelected = desk.id == store.overviewSelectionDeskID && board.id == store.overviewSelectionBoardID
        return Button {
            store.selectBoardInOverview(board.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(board.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)

                Text(
                    board.currentSheetURL?.host(percentEncoded: false)
                        ?? board.currentSheetURL?.absoluteString ?? ""
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Capsule()
                        .fill(.secondary.opacity(0.35))
                        .frame(width: max(24, min(92, board.width / 9)), height: 5)

                }
            }
            .padding(10)
            .frame(width: 158, height: 96, alignment: .leading)
            .foregroundStyle(.primary)
            .background(
                Color.primary.opacity(isSelected ? 0.18 : 0.09),
                in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                    .stroke(
                        isSelected ? .cyan.opacity(0.86) : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}
