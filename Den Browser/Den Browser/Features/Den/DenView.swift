import SwiftUI

struct DenView<Header: View>: View {
    private let profileName: String?
    private let profileColor: Color
    private let shouldShowHeader: Bool
    private let header: Header

    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var urlText = ""
    @State private var openBoardAfterBoardID: UUID?
    @State private var editBoardLinkText = ""
    @State private var saveDeskPresetLabel = ""
    @State private var saveDeskPresetMessage: String?
    @State private var zmxDuplicationText = ""

    @FocusState private var isOpenPanelFocused: Bool
    @FocusState private var isEditBoardLinkPanelFocused: Bool
    @FocusState private var isSaveDeskPresetLabelFocused: Bool
    @FocusState private var isZmxDuplicationPanelFocused: Bool
    @State private var renameText = ""
    @FocusState private var isRenamePanelFocused: Bool
    @FocusState private var isDeskFilterFocused: Bool

    init(
        profileName: String? = nil,
        profileColor: Color = .blue,
        shouldShowHeader: Bool,
        @ViewBuilder header: () -> Header
    ) {
        self.profileName = profileName
        self.profileColor = profileColor
        self.shouldShowHeader = shouldShowHeader
        self.header = header()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                boardStrip(in: geometry.size)
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

                if shouldShowHeader {
                    header
                }

                if store.isDeskFilterPresented && store.filteredDeskBoards.isEmpty {
                    ContentUnavailableView.search(text: store.deskFilterQuery)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }

                if store.isDeskFilterPresented {
                    deskFilterOverlay
                        .padding(
                            .top,
                            shouldShowHeader
                                ? DenLayout.denHeaderHeight + DenLayout.outerInset
                                : DenLayout.outerInset
                        )
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                        .zIndex(2)
                }

                activePanel(defaultBoardWidth: defaultBoardWidth(in: geometry.size))

                if store.isDrawerOpen {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.closeDrawer()
                        }
                        .accessibilityHidden(true)
                        .zIndex(2)
                }

                DrawerView(
                    availableHeight: geometry.size.height,
                    profileColor: profileColor,
                    shouldShowHeader: shouldShowHeader
                )
                .padding(.horizontal, DenLayout.outerInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: store.isDrawerOpen ? 0 : geometry.size.height)
                .allowsHitTesting(store.isDrawerOpen)
                .accessibilityHidden(!store.isDrawerOpen)
                .zIndex(3)

                if let toast = store.toastMessage {
                    ToastView(toast: toast, onTap: store.handleToastTap)
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(
                            systemReduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity)
                        )
                        .zIndex(10)
                }
            }
            .onChange(of: preferences.sheetScale) { _, scale in
                store.applySheetScale(scale)
            }
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.temporaryContext)
            .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.isDeskFilterPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.isZenViewPresented)
            .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.isDrawerOpen)
        }
        .background(DenBackground(isDenMode: store.isDenMode, profileColor: profileColor))
        .frame(minWidth: 800, minHeight: 720)
        .navigationTitle(titlebarTitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("den-content")
        .accessibilityLabel(contentAccessibilityValue)
        .accessibilityValue(contentAccessibilityValue)
        .modifier(DenDialogs())
    }

    private var contentAccessibilityValue: String {
        let inputContext = store.isDenMode ? "Den Mode" : store.contentInputLabel
        return store.isFocusModePresented ? "\(inputContext), Focus Mode" : inputContext
    }

    private var titlebarTitle: String {
        let profileTitle = profileName ?? "Den"
        guard store.temporaryContext == nil, store.focusedBoard != nil else {
            return profileTitle
        }
        return "\(profileTitle) · \(store.isDenMode ? "DEN MODE" : store.contentInputLabel.uppercased())"
    }

    private var deskFilterOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(store.isDeskFilterInputActive ? .primary : .secondary)

            TextField(
                text: Binding(
                    get: { store.deskFilterQuery },
                    set: { store.setDeskFilterQuery($0) }
                ),
                prompt: Text("Filter boards")
            ) {
                Text("Filter Boards")
            }
            .labelsHidden()
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
        case .essentialsPrefix:
            panelOverlay(essentialsPrefixPanel)
        case .openBoard:
            panelOverlay(openBoardPanel(defaultBoardWidth: defaultBoardWidth))
        case .zmxDuplication:
            panelOverlay(zmxDuplicationPanel)
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
            .padding(
                .top,
                shouldShowHeader
                    ? DenLayout.denHeaderHeight + DenLayout.panelGap
                    : DenLayout.outerInset
            )
            .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
    }

    private var newDeskPanel: some View {
        NewDeskPanel()
    }

    private var essentialsPrefixPanel: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemImage: "sparkles") {
                Text("Essentials")
                    .font(.headline)
            }

            if store.essentials.isEmpty {
                Text("No Essentials configured.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DenPanelLayout.controlSpacing) {
                        ForEach(store.essentials) { essential in
                            HStack(spacing: DenPanelLayout.controlSpacing) {
                                Text("g \(essential.displayKey)")
                                    .font(.caption.monospaced().weight(.semibold))
                                    .frame(width: 42, alignment: .leading)
                                Text(essential.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Text("Press Escape to cancel")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .denPanel(width: 300)
    }

    private var saveDeskPresetPanel: some View {
        SaveDeskPresetPanel(
            label: $saveDeskPresetLabel,
            message: $saveDeskPresetMessage,
            isFocused: $isSaveDeskPresetLabelFocused,
            onSave: saveDeskPreset)
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
            message: store.openBoardPanelMessage,
            onSubmit: { openBoard(defaultBoardWidth: $0) },
            onOpenRecent: { item, width in
                openBoard(item, defaultBoardWidth: width)
            },
            onClearRecent: store.clearRecent,
            onDismiss: dismissOpenBoardPanel,
            onInputChange: { store.openBoardPanelMessage = nil }
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

    private var zmxDuplicationPanel: some View {
        ZmxDuplicationPanel(
            text: zmxDuplicationTextBinding,
            isFocused: $isZmxDuplicationPanelFocused,
            sourceSessionName: store.focusedBoard?.zmxSessionName ?? "zmx",
            onSubmit: duplicateFocusedZmxBoard,
            onDismiss: dismissZmxDuplicationPanel)
    }

    private var zmxDuplicationTextBinding: Binding<String> {
        Binding(
            get: { zmxDuplicationText },
            set: { zmxDuplicationText = ZmxSessionNameGenerator.normalizedSuffix($0) })
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

    private func duplicateFocusedZmxBoard() {
        guard store.duplicateFocusedZmxBoard(suffix: zmxDuplicationText) else { return }
        zmxDuplicationText = ""
        restoreFocusedSheetFirstResponder()
    }

    private func dismissZmxDuplicationPanel() {
        store.hideZmxDuplicationPanel()
        zmxDuplicationText = ""
        restoreFocusedSheetFirstResponder()
    }

    private func restoreFocusedSheetFirstResponder() {
        DispatchQueue.main.async {
            let target: NSView?
            if let webView = store.focusedRuntime?.webView {
                target = webView
            } else {
                target = store.focusedTerminalRuntime?.terminalView
            }
            guard let target, let window = target.window,
                needsFirstResponderActivation(window.firstResponder, target: target)
            else { return }
            _ = window.makeFirstResponder(target)
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

    private func boardStrip(in size: CGSize) -> some View {
        BoardStrip(
            size: size,
            shouldShowHeader: shouldShowHeader,
            profileColor: profileColor,
            boardSpacing: DenLayout.outerInset,
            boardHorizontalPadding: DenLayout.outerInset,
            onOpenBoardAtEnd: { boardID in
                openBoardAfterBoardID = boardID
                store.showOpenBoardPanel()
            }
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

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

}

extension DenView where Header == EmptyView {
    init(profileName: String? = nil, profileColor: Color = .blue) {
        self.init(profileName: profileName, profileColor: profileColor, shouldShowHeader: false) {
            EmptyView()
        }
    }
}

#Preview {
    DenView()
        .environment(DenStore())
        .environment(AppPreferences())
}
