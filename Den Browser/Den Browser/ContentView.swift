//
//  ContentView.swift
//  Den Browser
//
//  Created by 大澤弘明 on 2026/07/10.
//

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
    @State private var newDeskLabel = ""
    @State private var selectedDeskTemplate: DeskTemplateSelection = .builtIn(.empty)
    @State private var activeDeskTemplate: DeskTemplateSelection = .builtIn(.empty)
    @State private var deskTemplateQuery = ""
    @State private var isManagingDeskTemplates = false
    @State private var isChoosingDeskTemplate = true
    @State private var didAttemptDeskCreation = false
    @State private var saveDeskTemplateLabel = ""
    @State private var saveDeskTemplateMessage: String?
    @State private var boardScrollPosition = ScrollPosition(idType: UUID.self)
    @State private var didScrollToRestoredFocusedBoard = false
    @State private var resizingBoardID: UUID?
    @State private var boardFrames: [UUID: CGRect] = [:]
    @State private var boardDrag: BoardDragState?
    @State private var lastBoardAutoScrollTime = 0.0
    @FocusState private var isOpenPanelFocused: Bool
    @FocusState private var isDeskTemplateSearchFocused: Bool
    @FocusState private var isNewDeskLabelFocused: Bool
    @FocusState private var isSaveDeskTemplateLabelFocused: Bool

    init(profileName: String? = nil, profileColor: Color = .blue) {
        self.profileName = profileName
        self.profileColor = profileColor
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                DenBackground(isDenMode: store.isDenMode, profileColor: profileColor)

                if store.focusedDesk?.boards.isEmpty == false {
                    boardStrip(in: geometry.size)
                        .allowsHitTesting(store.temporaryContext == nil)
                        .accessibilityHidden(store.temporaryContext != nil)
                } else {
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

                if store.isSaveDeskTemplatePanelPresented {
                    saveDeskTemplatePanel
                        .padding(.top, shouldShowDeskSwitcher ? 74 : 12)
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                }

                if store.isKeyboardShortcutsPresented,
                    store.focusedDesk?.boards.isEmpty == false
                {
                    KeyboardShortcutsView(onClose: store.hideKeyboardShortcuts)
                        .padding(18)
                        .frame(width: 760, height: 560)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            .onChange(of: store.state.focusedDeskID) { _, deskID in
                if boardDrag?.deskID != deskID {
                    cancelBoardDrag()
                }
            }
            .onChange(of: store.temporaryContext) { _, context in
                if context != nil {
                    cancelBoardDrag()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                cancelBoardDrag()
            }
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isOpenBoardPanelPresented)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isNewDeskPanelPresented)
            .animation(
                DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isSaveDeskTemplatePanelPresented
            )
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isOverviewPresented)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isKeyboardShortcutsPresented)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isBoardWidthPanelPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.isZenViewPresented)
            .overlay {
                if store.isDenMode {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.cyan.opacity(0.72), lineWidth: 1)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .navigationTitle(titlebarTitle)
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
            "Replace \(store.deskTemplatePendingReplacement?.label ?? "Desk Template")?",
            isPresented: Binding(
                get: { store.deskTemplatePendingReplacement != nil },
                set: { if !$0 { store.cancelDeskTemplateReplacement() } })
        ) {
            Button("Replace Template") {
                store.confirmDeskTemplateReplacement()
                store.hideSaveDeskTemplatePanel()
            }
            Button("Cancel", role: .cancel) { store.cancelDeskTemplateReplacement() }
        } message: {
            Text("Existing Desks will not be affected.")
        }
        .confirmationDialog(
            "Delete \(store.deskTemplatePendingDeletion?.label ?? "Desk Template")?",
            isPresented: Binding(
                get: { store.deskTemplatePendingDeletion != nil },
                set: { if !$0 { store.cancelDeskTemplateDeletion() } })
        ) {
            Button("Delete Template", role: .destructive) { confirmDeskTemplateDeletion() }
            Button("Cancel", role: .cancel) { store.cancelDeskTemplateDeletion() }
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
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(store.state.desks) { desk in
                            deskSwitcherButton(desk)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.state.focusedDeskID) { _, deskID in
                withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                    proxy.scrollTo(deskID, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func deskSwitcherButton(_ desk: DeskState) -> some View {
        if desk.id == store.state.focusedDeskID {
            deskButton(desk)
                .buttonStyle(.glassProminent)
                .id(desk.id)
        } else {
            deskButton(desk)
                .buttonStyle(.glass)
                .tint(.clear)
                .id(desk.id)
        }
    }

    private func deskButton(_ desk: DeskState) -> some View {
        Button {
            store.focusDesk(desk.id)
        } label: {
            Text(desk.label)
                .lineLimit(1)
                .frame(maxWidth: 180)
        }
    }

    private var newDeskPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(
                    systemName: store.isDeskTemplateManagementPresented
                        ? "bookmark" : "rectangle.stack.badge.plus"
                )
                .foregroundStyle(.secondary)
                Text(store.isDeskTemplateManagementPresented ? "Manage Templates" : "New Desk")
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(height: 38)

            if isChoosingDeskTemplate {
                DeskTemplatePicker(
                    selection: $activeDeskTemplate,
                    query: $deskTemplateQuery,
                    isManaging: $isManagingDeskTemplates,
                    isSearchFocused: $isDeskTemplateSearchFocused,
                    onConfirm: confirmDeskTemplate)
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deskTemplateLabel(for: selectedDeskTemplate))
                            .font(.headline)
                        Text(boardCountLabel(selectedDeskTemplateBoards.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change Template") { beginDeskTemplateSelection() }
                        .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))

                DeskTemplatePreview(boards: selectedDeskTemplateBoards)

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
                        beginDeskTemplateSelection()
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            selectedDeskTemplate = .builtIn(.empty)
            activeDeskTemplate = .builtIn(.empty)
            newDeskLabel = BuiltInDeskTemplate.empty.label
            deskTemplateQuery = ""
            isManagingDeskTemplates = store.isDeskTemplateManagementPresented
            isChoosingDeskTemplate = true
            didAttemptDeskCreation = false
            DispatchQueue.main.async {
                isDeskTemplateSearchFocused = true
            }
        }
        .onExitCommand {
            if isChoosingDeskTemplate {
                store.hideNewDeskPanel()
            } else {
                beginDeskTemplateSelection()
            }
        }
    }

    private var saveDeskTemplatePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .foregroundStyle(.secondary)
                Text("Save Desk as Template")
                    .font(.system(size: 17, weight: .semibold))
            }

            TextField("Template label", text: $saveDeskTemplateLabel)
                .textFieldStyle(.roundedBorder)
                .focused($isSaveDeskTemplateLabelFocused)
                .onSubmit(saveDeskTemplate)

            DeskTemplatePreview(
                boards: store.focusedDesk?.boards.map(DeskTemplateBoard.init) ?? [])

            HStack {
                Text(saveDeskTemplateMessage ?? "Captures the current Board arrangement")
                    .font(.caption)
                    .foregroundStyle(saveDeskTemplateMessage == nil ? Color.secondary : Color.red)
                Spacer()
                Button("Save Template", action: saveDeskTemplate)
                    .buttonStyle(.glassProminent)
                    .disabled(saveDeskTemplateLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            saveDeskTemplateLabel = store.focusedDesk?.label ?? ""
            saveDeskTemplateMessage = nil
            DispatchQueue.main.async { isSaveDeskTemplateLabelFocused = true }
        }
        .onExitCommand { store.hideSaveDeskTemplatePanel() }
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
        switch selectedDeskTemplate {
        case .builtIn(let template):
            store.createDesk(label: newDeskLabel, template: template)
        case .personal(let id):
            store.createDesk(label: newDeskLabel, personalTemplateID: id)
        }
        newDeskLabel = ""
        selectedDeskTemplate = .builtIn(.empty)
        didAttemptDeskCreation = false
    }

    private func confirmDeskTemplate(_ selection: DeskTemplateSelection) {
        activeDeskTemplate = selection
        selectedDeskTemplate = selection
        newDeskLabel = deskTemplateLabel(for: selection)
        isChoosingDeskTemplate = false
        didAttemptDeskCreation = false
        DispatchQueue.main.async {
            isNewDeskLabelFocused = true
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    private func beginDeskTemplateSelection() {
        activeDeskTemplate = selectedDeskTemplate
        isChoosingDeskTemplate = true
        isManagingDeskTemplates = false
        DispatchQueue.main.async { isDeskTemplateSearchFocused = true }
    }

    private func deskTemplateLabel(for selection: DeskTemplateSelection) -> String {
        switch selection {
        case .builtIn(let template):
            template.label
        case .personal(let id):
            store.deskTemplates.first(where: { $0.id == id })?.label ?? BuiltInDeskTemplate.empty.label
        }
    }

    private var selectedDeskTemplateBoards: [DeskTemplateBoard] {
        switch selectedDeskTemplate {
        case .builtIn(let template):
            template.boards
        case .personal(let id):
            store.deskTemplates.first(where: { $0.id == id })?.boards ?? []
        }
    }

    private func boardCountLabel(_ count: Int) -> String {
        count == 1 ? "1 Board" : "\(count) Boards"
    }

    private func saveDeskTemplate() {
        switch store.saveFocusedDeskAsTemplate(label: saveDeskTemplateLabel) {
        case .created:
            store.hideSaveDeskTemplatePanel()
        case .replacementPending:
            saveDeskTemplateMessage = nil
        case .invalidLabel:
            saveDeskTemplateMessage = "Enter a Template label"
        case .emptyDesk:
            saveDeskTemplateMessage = "A Personal Desk Template needs at least one Board"
        case .reservedLabel:
            saveDeskTemplateMessage = "Built-in Desk Template labels are reserved"
        }
    }

    private func confirmDeskTemplateDeletion() {
        if case .personal(let id) = selectedDeskTemplate,
            let pending = store.deskTemplatePendingDeletion,
            pending.id == id
        {
            if newDeskLabel == pending.label {
                newDeskLabel = BuiltInDeskTemplate.empty.label
            }
            selectedDeskTemplate = .builtIn(.empty)
        }
        store.confirmDeskTemplateDeletion()
    }

    private var shouldShowDeskSwitcher: Bool {
        stateHasMultipleDesks && !store.isZenViewPresented
    }

    private var stateHasMultipleDesks: Bool {
        store.state.desks.count > 1
    }

    private func defaultBoardWidth(in size: CGSize) -> Double {
        (size.width - boardHorizontalPadding * 2 - boardSpacing) / 2
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            DispatchQueue.main.async {
                isOpenPanelFocused = true
            }
        }
        .onExitCommand {
            store.hideOpenBoardPanel()
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
                    ?? "Changes every Board in the Focused Desk. Press 1–9 or Escape."
            )
            .font(.system(size: 12))
            .foregroundStyle(store.boardWidthPanelMessage == nil ? Color.secondary : Color.red)
        }
        .padding(16)
        .frame(width: 420)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onExitCommand {
            store.hideBoardWidthPanel()
        }
    }

    private func boardStrip(in size: CGSize) -> some View {
        let boards = store.focusedDesk?.boards ?? []
        let topInset: CGFloat = shouldShowDeskSwitcher ? 48 : 10
        let bottomInset: CGFloat = 10
        let boardHeight = max(420, size.height - topInset - bottomInset)
        let maximizedBoardWidth = max(280, size.width - boardHorizontalPadding * 2)
        let firstBoardWidth =
            boards.first.map {
                store.maximizedBoardID == $0.id ? maximizedBoardWidth : $0.width
            } ?? size.width
        let lastBoardWidth =
            boards.last.map {
                store.maximizedBoardID == $0.id ? maximizedBoardWidth : $0.width
            } ?? size.width
        let leadingPadding = max(boardHorizontalPadding, (size.width - firstBoardWidth) / 2)
        let trailingPadding = max(boardHorizontalPadding, (size.width - lastBoardWidth) / 2)

        return ScrollView(.horizontal) {
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
                        onDragChanged: { updateBoardDrag(board, value: $0, in: size) },
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
            .scrollTargetLayout()
            .padding(.leading, leadingPadding)
            .padding(.trailing, trailingPadding)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: boards.map(\.id))
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: boards.map(\.width))
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.maximizedBoardID)
        }
        .coordinateSpace(name: BoardStripCoordinateSpace.name)
        .scrollPosition($boardScrollPosition, anchor: .center)
        .scrollIndicators(.hidden)
        .onPreferenceChange(BoardFramePreferenceKey.self) { frames in
            boardFrames = frames
            alignDraggedBoard(to: frames)
        }
        .onAppear {
            guard !didScrollToRestoredFocusedBoard else { return }
            didScrollToRestoredFocusedBoard = true
            centerBoard(store.focusedDesk?.focusedBoardID, animated: false)
        }
        .onChange(of: store.focusedDesk?.focusedBoardID) { _, focusedBoardID in
            centerBoard(focusedBoardID)
        }
        .onChange(of: store.centerFocusedBoardRequest) { _, _ in
            centerBoard(store.focusedDesk?.focusedBoardID)
        }
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

    private func updateBoardLayout(for size: CGSize) {
        store.updateBoardLayout(
            availableWidth: size.width - boardHorizontalPadding * 2,
            spacing: boardSpacing
        )
    }

    private func updateBoardDrag(_ board: BoardState, value: DragGesture.Value, in size: CGSize) {
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
            index < boards.count - 1
        {
            let next = boards[index + 1]
            guard let frame = boardFrames[next.id], drag.desiredCenterX > frame.midX else { break }
            store.previewBoardMove(drag.boardID, to: index + 1)
            drag.offset.width -= next.width + boardSpacing
            boardDrag = drag
        }

        while let boards = store.focusedDesk?.boards,
            let index = deskIndex(of: drag.boardID),
            index > 0
        {
            let previous = boards[index - 1]
            guard let frame = boardFrames[previous.id], drag.desiredCenterX < frame.midX else { break }
            store.previewBoardMove(drag.boardID, to: index - 1)
            drag.offset.width += previous.width + boardSpacing
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

    private func autoScrollBoardStrip(at location: CGPoint, in size: CGSize) {
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
            .accessibilityLabel("Resize \(board.label) board")
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
            colors: [
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
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button("Open Board", action: openBoard)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}

private struct OverviewView: View {
    @Environment(DenStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overview")
                .font(.system(size: 17, weight: .semibold))

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(store.state.desks) { desk in
                        deskRow(desk)
                    }
                }
                .padding(2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
    }

    private func deskRow(_ desk: DeskState) -> some View {
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
                if desk.boards.isEmpty {
                    Text("Empty")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 150, height: 88)
                        .background(
                            Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ForEach(desk.boards) { board in
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
                Text(board.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)

                Text(URL(string: board.currentURLString)?.host(percentEncoded: false) ?? board.currentURLString)
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
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? .cyan.opacity(0.86) : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

}
