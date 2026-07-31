import SwiftUI

struct DenView: View {
    private let profileName: String?
    private let profileColor: Color

    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @State private var urlText = ""
    @State private var openBoardAfterBoardID: UUID?
    @State private var editBoardLinkText = ""
    @State private var newDeskLabel = ""
    @State private var newDeskLabelSelection: TextSelection?
    @State private var selectedDeskPreset: DeskPresetSelection = .builtIn(.empty)
    @State private var activeDeskPreset: DeskPresetSelection = .builtIn(.empty)
    @State private var deskPresetQuery = ""
    @State private var isManagingDeskPresets = false
    @State private var isChoosingDeskPreset = true
    @State private var didAttemptDeskAction = false
    @State private var saveDeskPresetLabel = ""
    @State private var saveDeskPresetMessage: String?

    @State private var didScrollToRestoredFocusedBoard = false
    @State private var resizingBoardID: UUID?
    @State private var boardFrames: [UUID: CGRect] = [:]
    @State private var boardScrollPosition = ScrollPosition(idType: UUID.self)
    @State private var pendingBoardCentering: PendingBoardCentering?
    @State private var boardCenteringTask: Task<Void, Never>?
    @State private var boardDrag: BoardDragState?
    @State private var lastBoardAutoScrollTime = 0.0
    @State private var deskFrames: [UUID: CGRect] = [:]
    @State private var deskScrollPosition = ScrollPosition(idType: UUID.self)
    @State private var deskDrag: DeskDragState?
    @State private var lastDeskAutoScrollTime = 0.0
    @FocusState private var isOpenPanelFocused: Bool
    @FocusState private var isEditBoardLinkPanelFocused: Bool
    @FocusState private var isDeskPresetSearchFocused: Bool
    @FocusState private var isNewDeskLabelFocused: Bool
    @FocusState private var isSaveDeskPresetLabelFocused: Bool
    @State private var renameText = ""
    @FocusState private var isRenamePanelFocused: Bool
    @FocusState private var isDeskFilterFocused: Bool

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
                        .padding(.top, DenLayout.outerInset)
                        .allowsHitTesting(store.temporaryContext == nil)
                        .accessibilityHidden(store.temporaryContext != nil)
                }

                if store.isDeskFilterPresented && store.filteredDeskBoards.isEmpty {
                    ContentUnavailableView.search(text: store.deskFilterQuery)
                        .allowsHitTesting(false)
                }

                if store.isDeskFilterPresented {
                    deskFilterOverlay
                        .padding(
                            .top,
                            shouldShowDeskSwitcher
                                ? DenLayout.boardTopInsetWithDeskSwitcher + DenLayout.outerInset
                                : DenLayout.outerInset
                        )
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                        .zIndex(2)
                }

                activePanel(defaultBoardWidth: defaultBoardWidth(in: geometry.size))

                DrawerView(
                    availableHeight: geometry.size.height,
                    profileColor: profileColor
                )
                .padding(.horizontal, DenLayout.outerInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: store.isDrawerOpen ? 0 : geometry.size.height)
                .allowsHitTesting(store.isDrawerOpen)
                .accessibilityHidden(!store.isDrawerOpen)
                .zIndex(3)

                if let toast = store.toastMessage {
                    ToastView(toast: toast)
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(
                            systemReduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity)
                        )
                        .allowsHitTesting(false)
                        .zIndex(10)
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
            .onChange(of: appearsActive) { _, isActive in
                if !isActive {
                    cancelBoardDrag()
                    cancelDeskDrag()
                }
            }
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.temporaryContext)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isDeskFilterPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.isZenViewPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.isDrawerOpen)
        }
        .background(DenBackground(isDenMode: store.isDenMode, profileColor: profileColor))
        .frame(minWidth: 1100, minHeight: 720)
        .navigationTitle(titlebarTitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("den-content")
        .accessibilityValue(store.isDenMode ? "Den Mode" : "Sheet Input")
        .modifier(DenDialogs(confirmDeskPresetDeletion: confirmDeskPresetDeletion))
    }

    private var titlebarTitle: String {
        let profilePrefix = profileName.map { "\($0) · " } ?? ""
        guard store.isDenMode else { return profileName.map { "\($0) — Den Browser" } ?? "Den Browser" }
        return profilePrefix + "DEN MODE"
    }

    private var deskSwitcher: some View {
        DeskSwitcher(
            scrollPosition: $deskScrollPosition,
            shouldReduceMotion: shouldReduceMotion,
            item: { desk, number, size in
                AnyView(deskSwitcherItem(desk, number: number, in: size))
            },
            onFramesChange: { frames in
                deskFrames = frames
                alignDraggedDesk(to: frames)
            }
        )
    }

    private var deskFilterOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(store.isDeskFilterInputActive ? .primary : .secondary)

            TextField(
                "Filter Boards (/)",
                text: Binding(
                    get: { store.deskFilterQuery },
                    set: { store.setDeskFilterQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .focused($isDeskFilterFocused)
            .disabled(!store.isDeskFilterInputActive)
            .accessibilityIdentifier("desk-filter-input")

            Text("\(store.filteredDeskBoards.count)/\(store.focusedDesk?.boards.count ?? 0)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: DenLayout.deskFilterWidth)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .stroke(
                    store.isDeskFilterInputActive
                        ? profileColor.opacity(0.86)
                        : Color.primary.opacity(0.16),
                    lineWidth: store.isDeskFilterInputActive ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        .onTapGesture {
            store.enterDeskFilter()
        }
        .onAppear {
            DispatchQueue.main.async {
                isDeskFilterFocused = store.isDeskFilterInputActive
            }
        }
        .onChange(of: store.isDeskFilterInputActive) { _, isActive in
            isDeskFilterFocused = isActive
        }
        .accessibilityIdentifier("desk-filter")
    }

    @ViewBuilder
    private func activePanel(defaultBoardWidth: CGFloat) -> some View {
        switch store.temporaryContext {
        case .openBoard:
            panelOverlay(openBoardPanel(defaultBoardWidth: defaultBoardWidth))
        case .editBoardLink:
            panelOverlay(editBoardLinkPanel)
        case .newDesk, .replaceDesk, .deskPresetManagement:
            panelOverlay(newDeskPanel)
        case .boardWidth:
            panelOverlay(boardWidthPanel)
        case .saveDeskPreset:
            panelOverlay(saveDeskPresetPanel)
        case .renameBoard:
            panelOverlay(renameBoardPanel)
        case .renameDesk:
            panelOverlay(renameDeskPanel)
        case .overview:
            OverviewView(profileColor: profileColor)
                .padding(DenLayout.overlayInset)
                .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.98))
        case .keyboardShortcuts:
            if store.focusedDesk?.boards.isEmpty == false {
                KeyboardShortcutsView(onClose: store.hideKeyboardShortcuts)
                    .padding(DenKeyboardShortcutsLayout.guidePadding)
                    .frame(
                        width: DenKeyboardShortcutsLayout.guideSize.width,
                        height: DenKeyboardShortcutsLayout.guideSize.height
                    )
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous)
                    )
                    .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.98))
            }
        case .drawer, nil:
            EmptyView()
        }
    }

    private func panelOverlay<Content: View>(_ content: Content) -> some View {
        content
            .padding(.top, shouldShowDeskSwitcher ? DenLayout.panelTopInset : DenLayout.outerInset)
            .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
    }

    @ViewBuilder
    private func deskSwitcherButton(_ desk: DeskState, number: Int, in size: CGSize) -> some View {
        deskButton(desk, number: number, in: size)
            .id(desk.id)
    }

    private func deskSwitcherItem(_ desk: DeskState, number: Int, in size: CGSize) -> some View {
        let isDragged = deskDrag?.deskID == desk.id
        let offset = isDragged ? deskDrag?.offset ?? 0 : 0
        return deskSwitcherButton(desk, number: number, in: size)
            .offset(x: offset)
            .background(deskFrameBackground(for: desk.id))
            .zIndex(isDragged ? 2 : 1)
    }

    private func deskButton(_ desk: DeskState, number: Int, in size: CGSize) -> some View {
        Text("\(number). \(desk.label)")
            .lineLimit(1)
            .frame(maxWidth: DenLayout.deskButtonMaxWidth)
            .padding(.horizontal, DenLayout.chromeHorizontalPadding)
            .frame(height: DenLayout.deskButtonHeight)
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
                    store.focusDesk(desk.id)
                    store.captureFocusedDeskScreenshot()
                } label: {
                    Label("Capture Desk Screenshot...", systemImage: "camera.on.rectangle")
                }
                .disabled(desk.boards.isEmpty)

                Button {
                    store.focusDesk(desk.id)
                    store.showReplaceDeskPanel()
                } label: {
                    Label("Replace Desk...", systemImage: "rectangle.stack.badge.minus")
                }

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
                    .onChanged { updateDeskDrag(desk, value: $0, in: size) }
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
        NewDeskPanel(
            selectedDeskPreset: $selectedDeskPreset,
            activeDeskPreset: $activeDeskPreset,
            query: $deskPresetQuery,
            isManaging: $isManagingDeskPresets,
            isChoosing: $isChoosingDeskPreset,
            didAttemptAction: $didAttemptDeskAction,
            newDeskLabel: $newDeskLabel,
            newDeskLabelSelection: $newDeskLabelSelection,
            isSearchFocused: $isDeskPresetSearchFocused,
            isLabelFocused: $isNewDeskLabelFocused,
            selectedBoards: selectedDeskPresetBoards,
            presetLabel: deskPresetLabel(for: selectedDeskPreset),
            boardCountLabel: boardCountLabel(selectedDeskPresetBoards.count),
            trimmedLabel: trimmedNewDeskLabel,
            description: newDeskPanelDescription,
            onConfirmPreset: confirmDeskPreset,
            onBeginSelection: beginDeskPresetSelection,
            onSubmit: submitDeskPreset)
    }

    private var saveDeskPresetPanel: some View {
        SaveDeskPresetPanel(
            label: $saveDeskPresetLabel,
            message: $saveDeskPresetMessage,
            isFocused: $isSaveDeskPresetLabelFocused,
            onSave: saveDeskPreset)
    }

    private var trimmedNewDeskLabel: String {
        newDeskLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var newDeskPanelDescription: String {
        if store.isReplaceDeskPanelPresented {
            return store.focusedDesk?.boards.isEmpty == false
                ? "Existing Boards will be removed after confirmation"
                : "Applies this arrangement to the focused Desk"
        }
        return store.canCreateDesk ? "New desk opens after the focused desk" : "A Den can contain up to 10 desks"
    }

    private func submitDeskPreset() {
        didAttemptDeskAction = true
        guard !trimmedNewDeskLabel.isEmpty else { return }
        if store.isReplaceDeskPanelPresented {
            let result: DeskReplacementResult?
            switch selectedDeskPreset {
            case .builtIn(let preset):
                result = store.replaceFocusedDesk(label: newDeskLabel, preset: preset)
            case .personal(let id):
                result = store.replaceFocusedDesk(label: newDeskLabel, personalPresetID: id)
            }
            if result == .applied {
                resetDeskPresetPanel()
            }
            return
        }

        switch selectedDeskPreset {
        case .builtIn(let preset):
            store.createDesk(label: newDeskLabel, preset: preset)
        case .personal(let id):
            store.createDesk(label: newDeskLabel, personalPresetID: id)
        }
        resetDeskPresetPanel()
    }

    private func resetDeskPresetPanel() {
        newDeskLabel = ""
        selectedDeskPreset = .builtIn(.empty)
        didAttemptDeskAction = false
    }

    private func confirmDeskPreset(_ selection: DeskPresetSelection) {
        let label = deskPresetLabel(for: selection)
        activeDeskPreset = selection
        selectedDeskPreset = selection
        newDeskLabel = label
        newDeskLabelSelection = TextSelection(range: label.startIndex..<label.endIndex)
        isChoosingDeskPreset = false
        didAttemptDeskAction = false
        DispatchQueue.main.async { isNewDeskLabelFocused = true }
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
            let fallback: DeskPresetSelection =
                store.isReplaceDeskPanelPresented ? .builtIn(.chatGPT) : .builtIn(.empty)
            if newDeskLabel == pending.label {
                newDeskLabel = deskPresetLabel(for: fallback)
            }
            selectedDeskPreset = fallback
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
        return (size.width - DenLayout.outerInset * 2 - DenLayout.outerInset) / 2
    }

    private func openBoardPanel(defaultBoardWidth: Double) -> some View {
        OpenBoardPanel(
            urlText: $urlText,
            isFocused: $isOpenPanelFocused,
            defaultBoardWidth: defaultBoardWidth,
            initialURL: store.openBoardPanelInitialURL,
            recentItems: store.recentItems,
            onSubmit: { openBoard(defaultBoardWidth: $0) },
            onOpenRecent: { item, width in
                openBoard(item, defaultBoardWidth: width)
            },
            onClearRecent: store.clearRecent,
            onDismiss: dismissOpenBoardPanel
        )
    }

    private var editBoardLinkPanel: some View {
        EditBoardLinkPanel(
            text: $editBoardLinkText,
            isFocused: $isEditBoardLinkPanelFocused,
            onSubmit: editFocusedBoardLink,
            onDismiss: dismissEditBoardLinkPanel
        )
    }

    private func dismissOpenBoardPanel() {
        store.hideOpenBoardPanel()
        openBoardAfterBoardID = nil
        restoreFocusedSheetFirstResponder()
    }

    private func dismissEditBoardLinkPanel() {
        store.hideEditBoardLinkPanel()
        restoreFocusedSheetFirstResponder()
    }

    private func restoreFocusedSheetFirstResponder() {
        DispatchQueue.main.async {
            guard let webView = store.focusedRuntime?.webView else { return }
            webView.window?.makeFirstResponder(webView)
        }
    }

    private var renameBoardPanel: some View {
        RenameBoardPanel(text: $renameText, isFocused: $isRenamePanelFocused)
    }

    private var renameDeskPanel: some View {
        RenameDeskPanel(text: $renameText, isFocused: $isRenamePanelFocused)
    }

    private var boardWidthPanel: some View {
        BoardWidthPanel()
    }

    private func boardStrip(in size: CGSize, safeAreaTop: CGFloat) -> some View {
        BoardStrip(
            boardDrag: $boardDrag,
            resizingBoardID: $resizingBoardID,
            scrollPosition: $boardScrollPosition,
            size: size,
            shouldShowDeskSwitcher: shouldShowDeskSwitcher,
            profileColor: profileColor,
            boardSpacing: DenLayout.outerInset,
            boardHorizontalPadding: DenLayout.outerInset,
            isPointerFocusEnabled: isBoardPointerFocusEnabled,
            onDragChanged: { board, value, size in
                updateBoardDrag(board, value: value, in: size)
            },
            onDragEnded: { value, size in
                finishBoardDrag(value: value, in: size)
            },
            onFramesChanged: { frames in
                boardFrames = frames
                alignDraggedBoard(to: frames)
                if let pendingBoardCentering,
                    frames[pendingBoardCentering.boardID] != nil
                {
                    self.pendingBoardCentering = nil
                    boardCenteringTask?.cancel()
                    boardCenteringTask = Task { @MainActor in
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        performBoardCentering(
                            pendingBoardCentering.boardID,
                            animated: pendingBoardCentering.animated)
                    }
                }
            },
            onOpenBoardAtEnd: { boardID in
                openBoardAfterBoardID = boardID
                store.showOpenBoardPanel()
            },
            onAppear: { shouldCenterFocusedBoard, restingScrollX in
                guard !didScrollToRestoredFocusedBoard else { return }
                didScrollToRestoredFocusedBoard = true
                alignBoardStrip(
                    centersFocusedBoard: shouldCenterFocusedBoard,
                    restingScrollX: restingScrollX,
                    animated: false)
            },
            onAlignmentChanged: { previous, current in
                alignBoardStrip(
                    centersFocusedBoard: current.centersFocusedBoard,
                    boardID: current.boardID,
                    restingScrollX: current.restingScrollX,
                    animated: previous.deskID == current.deskID)
            },
            onCenterRequest: {
                centerBoard(store.focusedDesk?.focusedBoardID)
            }
        )
    }

    private func alignBoardStrip(
        centersFocusedBoard: Bool,
        boardID: UUID? = nil,
        restingScrollX: CGFloat = 0,
        animated: Bool = true
    ) {
        if centersFocusedBoard {
            centerBoard(boardID ?? store.focusedDesk?.focusedBoardID, animated: animated)
        } else {
            resetBoardStripPosition(to: restingScrollX, animated: animated)
        }
    }

    private func resetBoardStripPosition(to x: CGFloat = 0, animated: Bool) {
        pendingBoardCentering = nil
        boardCenteringTask?.cancel()
        if animated {
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                boardScrollPosition.scrollTo(x: x)
            }
        } else {
            boardScrollPosition.scrollTo(x: x)
        }
    }

    private func centerBoard(_ boardID: UUID?, animated: Bool = true) {
        guard resizingBoardID == nil, !store.isBoardDragging, let boardID else { return }
        guard boardFrames[boardID] != nil else {
            pendingBoardCentering = PendingBoardCentering(
                boardID: boardID,
                animated: animated)
            return
        }
        pendingBoardCentering = nil
        boardCenteringTask?.cancel()
        performBoardCentering(boardID, animated: animated)
    }

    private func performBoardCentering(_ boardID: UUID, animated: Bool) {
        if animated {
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                boardScrollPosition.scrollTo(id: boardID, anchor: .center)
            }
        } else {
            boardScrollPosition.scrollTo(id: boardID, anchor: .center)
        }
    }

    private func isBoardPointerFocusEnabled(for boardID: UUID) -> Bool {
        (boardDrag == nil || boardDrag?.boardID == boardID) && store.temporaryContext == nil
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    private func openBoard(defaultBoardWidth: Double) {
        store.openBoard(
            input: urlText,
            preferredWidth: defaultBoardWidth,
            afterBoardID: openBoardAfterBoardID)
        guard !store.isOpenBoardPanelPresented else { return }
        urlText = ""
        openBoardAfterBoardID = nil
    }

    private func openBoard(_ item: RecentItem, defaultBoardWidth: Double) {
        store.openBoard(
            recentItem: item,
            preferredWidth: defaultBoardWidth,
            afterBoardID: openBoardAfterBoardID)
        guard !store.isOpenBoardPanelPresented else { return }
        urlText = ""
        openBoardAfterBoardID = nil
    }

    private func editFocusedBoardLink() {
        if store.navigateFocusedBoard(urlString: editBoardLinkText) {
            editBoardLinkText = ""
        }
    }

    private func updateDeskDrag(
        _ desk: DeskState,
        value: DragGesture.Value,
        in size: CGSize
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
        autoScrollDeskSwitcher(at: value.location, in: size)
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
        in size: CGSize
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
            deskScrollPosition.scrollTo(id: targetID, anchor: .center)
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
            availableWidth: size.width - DenLayout.outerInset * 2,
            spacing: DenLayout.outerInset
        )
    }

    private func updateBoardDrag(
        _ board: BoardState,
        value: DragGesture.Value,
        in size: CGSize
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
        autoScrollBoardStrip(at: value.location, in: size)
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
            drag.offset.width += direction * (crossedBoard.width + DenLayout.outerInset)
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
        in size: CGSize
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
            boardScrollPosition.scrollTo(id: targetID, anchor: .center)
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
    }
}

private struct PendingBoardCentering {
    let boardID: UUID
    let animated: Bool
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

nonisolated enum DeskDragInsertion {
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

struct DeskFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

nonisolated enum BoardDragInsertion {
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

struct BoardDragState {
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

struct BoardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

#Preview {
    DenView()
        .environment(DenStore())
        .environment(AppPreferences())
}
