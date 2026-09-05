import SwiftUI

struct DenView<Header: View>: View {
    private let profileName: String?
    private let profileColor: Color
    private let shouldShowHeader: Bool
    private let header: Header

    @Environment(DenStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

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
                    DeskFilterOverlay(profileColor: profileColor)
                        .padding(
                            .top,
                            shouldShowHeader
                                ? DenLayout.denHeaderHeight + DenLayout.outerInset
                                : DenLayout.outerInset
                        )
                        .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                        .zIndex(2)
                }

                activePanel(
                    newBoardWidth: newBoardWidth(in: geometry.size),
                    boardHeight: DenLayout.boardHeight(
                        for: geometry.size,
                        shouldShowHeader: shouldShowHeader))

                notificationsOverlay
                drawerOverlay(in: geometry.size)
                toastOverlay
                indicatorOverlay
            }
            .onChange(of: preferences.sheetScale) { _, scale in
                store.applySheetScale(scale)
            }
            .onAppear {
                store.updateBoardLayout(
                    availableWidth: geometry.size.width - DenLayout.outerInset * 2,
                    spacing: DenLayout.outerInset
                )
            }
            .onChange(of: geometry.size.width) { _, width in
                store.updateBoardLayout(
                    availableWidth: width - DenLayout.outerInset * 2,
                    spacing: DenLayout.outerInset
                )
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

    @ViewBuilder
    private func activePanel(newBoardWidth: CGFloat, boardHeight: CGFloat) -> some View {
        switch store.temporaryContext {
        case .essentialsPrefix:
            panelOverlay(essentialsPrefixPanel)
        case .openBoard:
            panelOverlay(OpenBoardPanel(newBoardWidth: newBoardWidth))
        case .zmxSessions:
            panelOverlay(ZmxSessionsPanel(profileColor: profileColor))
        case .zmxDuplication:
            panelOverlay(ZmxDuplicationPanel())
        case .editBoardLink:
            panelOverlay(EditBoardLinkPanel())
        case .newDesk, .replaceDesk, .deskPresetManagement:
            panelOverlay(newDeskPanel)
        case .boardWidth:
            panelOverlay(boardWidthPanel)
        case .saveDeskPreset:
            panelOverlay(SaveDeskPresetPanel())
        case .renameBoard:
            panelOverlay(RenameBoardPanel())
        case .renameDesk:
            panelOverlay(RenameDeskPanel())
        case .saveEssential:
            panelOverlay(saveEssentialPanel)
        case .overview:
            OverviewView(profileColor: profileColor, boardHeight: boardHeight)
                .padding(DenLayout.overlayInset)
                .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.98))
        case .boardActivity:
            BoardActivityView(profileColor: profileColor)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("No Essentials configured.")
                    Text("Configure Essentials in Settings.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DenPanelLayout.controlSpacing) {
                        ForEach(store.essentials) { essential in
                            HStack(spacing: DenPanelLayout.controlSpacing) {
                                ShortcutChip(tokens: [essential.displayKey], width: 42)
                                Text(essential.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Text(
                store.essentials.isEmpty
                    ? "Press Escape to cancel"
                    : "Press an Essential key · Escape to cancel"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .denPanel(width: 300)
    }

    private func newBoardWidth(in size: CGSize) -> Double {
        DenLayout.newBoardWidth(in: size, focusedBoardWidth: store.focusedBoard?.width)
    }

    private var saveEssentialPanel: some View {
        SaveEssentialPanel()
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
                store.showOpenBoardPanel(afterBoardID: boardID)
            }
        )
    }

    @ViewBuilder
    private var notificationsOverlay: some View {
        if store.isNotificationListPresented {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture { store.closeNotificationList() }
                .accessibilityHidden(true)
                .zIndex(4)

            NotificationListView(profileColor: profileColor)
                .padding(
                    .top,
                    shouldShowHeader
                        ? DenLayout.denHeaderHeight + DenLayout.panelGap
                        : DenLayout.outerInset
                )
                .padding(.trailing, DenLayout.outerInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(DenMotion.transition(reduceMotion: shouldReduceMotion, scale: 0.96))
                .zIndex(5)
        }
    }

    @ViewBuilder
    private func drawerOverlay(in size: CGSize) -> some View {
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
            availableHeight: size.height,
            profileColor: profileColor,
            shouldShowHeader: shouldShowHeader
        )
        .padding(.horizontal, DenLayout.outerInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .offset(y: store.isDrawerOpen ? 0 : size.height)
        .allowsHitTesting(store.isDrawerOpen)
        .accessibilityHidden(!store.isDrawerOpen)
        .zIndex(3)
    }

    @ViewBuilder
    private var toastOverlay: some View {
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

    @ViewBuilder
    private var indicatorOverlay: some View {
        if shouldShowBoardIndicator {
            boardIndicator
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, DenLayout.outerInset)
                .allowsHitTesting(store.temporaryContext == nil)
                .accessibilityHidden(store.temporaryContext != nil)
                .transition(.opacity)
        }
    }

    private var shouldShowBoardIndicator: Bool {
        !store.isZenViewPresented
            && store.temporaryContext == nil
            && (store.focusedDesk?.boards.count ?? 0) > 1
    }

    private var boardIndicator: some View {
        let boards =
            store.isDeskFilterPresented
            ? store.filteredDeskBoards
            : store.focusedDesk?.boards ?? []
        let focusedBoardID =
            store.isDeskFilterPresented
            ? store.deskFilterSelectionBoardID
            : store.focusedDesk?.focusedBoardID

        return BoardStripIndicator(
            boards: boards,
            focusedBoardID: focusedBoardID,
            reduceMotion: shouldReduceMotion,
            onSelect: { store.focusBoard($0) }
        )
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

private struct DeskFilterOverlay: View {
    @Environment(DenStore.self) private var store
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let profileColor: Color
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(store.isDeskFilterInputActive ? .primary : .secondary)
                .accessibilityHidden(true)

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
            .focused($isFocused)
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
                        ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.86))
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
                isFocused = store.isDeskFilterInputActive
            }
        }
        .onChange(of: store.isDeskFilterInputActive) { _, isActive in
            isFocused = isActive
        }
        .accessibilityIdentifier("desk-filter")
    }
}

#Preview {
    DenView()
        .environment(DenStore())
        .environment(AppPreferences())
}

private struct BoardStripIndicator: View {
    private static let dotHeight: CGFloat = 6

    let boards: [BoardState]
    let focusedBoardID: UUID?
    let reduceMotion: Bool
    let onSelect: (UUID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(boards) { board in
                let isFocused = board.id == focusedBoardID
                Button {
                    onSelect(board.id)
                } label: {
                    Capsule()
                        .fill(isFocused ? Color.primary : Color.primary.opacity(0.28))
                        .frame(width: isFocused ? 18 : Self.dotHeight, height: Self.dotHeight)
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(board.displayName)
                .accessibilityLabel("\(board.displayName) Board")
            }
        }
        .frame(height: Self.dotHeight)
        .animation(DenMotion.spatial(reduceMotion: reduceMotion), value: focusedBoardID)
        .animation(DenMotion.spatial(reduceMotion: reduceMotion), value: boards.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-strip-indicator")
    }
}
