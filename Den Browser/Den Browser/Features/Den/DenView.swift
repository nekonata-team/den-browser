import AppKit
import SwiftUI

struct DenView: View {
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
    @State private var boardScrollPosition = ScrollPosition(idType: UUID.self)
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
                    OverviewView(profileColor: profileColor)
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
                    .strokeBorder(profileColor.opacity(0.48), lineWidth: 1)
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
            didAttemptCreation: $didAttemptDeskCreation,
            newDeskLabel: $newDeskLabel,
            isSearchFocused: $isDeskPresetSearchFocused,
            isLabelFocused: $isNewDeskLabelFocused,
            selectedBoards: selectedDeskPresetBoards,
            presetLabel: deskPresetLabel(for: selectedDeskPreset),
            boardCountLabel: boardCountLabel(selectedDeskPresetBoards.count),
            trimmedLabel: trimmedNewDeskLabel,
            description: newDeskPanelDescription,
            onConfirmPreset: confirmDeskPreset,
            onBeginSelection: beginDeskPresetSelection,
            onCreate: createDesk)
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
        OpenBoardPanel(
            urlText: $urlText,
            isFocused: $isOpenPanelFocused,
            defaultBoardWidth: defaultBoardWidth,
            onSubmit: { openBoard(defaultBoardWidth: $0) },
            onDismiss: store.hideOpenBoardPanel
        )
    }

    private var editBoardLinkPanel: some View {
        EditBoardLinkPanel(
            text: $editBoardLinkText,
            isFocused: $isEditBoardLinkPanelFocused,
            onSubmit: editFocusedBoardLink,
            onDismiss: store.hideEditBoardLinkPanel
        )
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
            boardSpacing: boardSpacing,
            boardHorizontalPadding: boardHorizontalPadding,
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
            },
            onAppear: {
                guard !didScrollToRestoredFocusedBoard else { return }
                didScrollToRestoredFocusedBoard = true
                centerBoard(store.focusedDesk?.focusedBoardID, animated: false)
            },
            onFocusChanged: { previous, current in
                centerBoard(current.boardID, animated: previous.deskID == current.deskID)
            },
            onCenterRequest: {
                centerBoard(store.focusedDesk?.focusedBoardID)
            }
        )
    }

    private func centerBoard(_ boardID: UUID?, animated: Bool = true) {
        guard resizingBoardID == nil, !store.isBoardDragging, let boardID else { return }

        if animated {
            withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                boardScrollPosition.scrollTo(id: boardID, anchor: .center)
            }
        } else {
            boardScrollPosition.scrollTo(id: boardID, anchor: .center)
        }
    }

    private var boardFocusTarget: BoardFocusTarget {
        BoardFocusTarget(
            deskID: store.state.focusedDeskID,
            boardID: store.focusedDesk?.focusedBoardID)
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
            availableWidth: size.width - boardHorizontalPadding * 2,
            spacing: boardSpacing
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

struct BoardFocusTarget: Equatable {
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
