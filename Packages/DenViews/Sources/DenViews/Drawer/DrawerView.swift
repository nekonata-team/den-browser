import DenDomain
import DenModels
import SFSafeSymbols
import SwiftUI

public struct DrawerView<Peek: View>: View {
    @Environment(DrawerModel.self) private var drawer
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let availableHeight: CGFloat
    let availableWidth: CGFloat
    let profileColor: Color
    var shouldShowHeader: Bool = true
    let isDenMode: () -> Bool
    let isDrawerOpen: () -> Bool
    let motionPreference: MotionPreference
    @ViewBuilder let peek: (DrawerItem, Bool) -> Peek
    let placeFromContextMenu: (UUID) -> Void
    let placeAsBoard: (UUID) -> Void

    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedDrawerItemID: UUID?

    public init(
        availableHeight: CGFloat, availableWidth: CGFloat, profileColor: Color,
        shouldShowHeader: Bool = true, isDenMode: @escaping () -> Bool, isDrawerOpen: @escaping () -> Bool,
        motionPreference: MotionPreference, @ViewBuilder peek: @escaping (DrawerItem, Bool) -> Peek,
        placeFromContextMenu: @escaping (UUID) -> Void, placeAsBoard: @escaping (UUID) -> Void
    ) {
        self.availableHeight = availableHeight
        self.availableWidth = availableWidth
        self.profileColor = profileColor
        self.shouldShowHeader = shouldShowHeader
        self.isDenMode = isDenMode
        self.isDrawerOpen = isDrawerOpen
        self.motionPreference = motionPreference
        self.peek = peek
        self.placeFromContextMenu = placeFromContextMenu
        self.placeAsBoard = placeAsBoard
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            drawerContents
        }
        .frame(width: drawerWidth, height: drawerHeight, alignment: .top)
        .glassEffect(in: drawerShape)
        .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: drawer.expandedItemID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer")
        .onAppear {
            restoreKeyboardFocus()
        }
        .onChange(of: isDenMode()) { _, _ in
            restoreKeyboardFocus()
        }
        .onChange(of: drawer.selectedItemID) { _, itemID in
            if isDenMode(), !drawer.isFilterInputActive {
                focusedDrawerItemID = itemID
            }
        }
        .onChange(of: drawer.expandedItemID) { _, _ in
            restoreKeyboardFocus()
        }
    }

    private var header: some View {
        DrawerHeaderView(
            isSearchFocused: $isSearchFocused,
            profileColor: profileColor
        )
        .onChange(of: drawer.isFilterInputActive) { _, newValue in
            if newValue {
                isSearchFocused = true
            } else {
                restoreKeyboardFocus()
            }
        }
        .onChange(of: drawer.query) { _, newValue in
            if isSearchFocused {
                TextInputComposition.syncActiveFieldEditor(to: newValue)
            }
        }
    }

    private var drawerContents: some View {
        ScrollViewReader { proxy in
            Group {
                if drawer.items.isEmpty {
                    ContentUnavailableView(
                        "Drawer is empty",
                        systemSymbol: .tray,
                        description: Text("Keep a Current Sheet here, or start a new Terminal from the header.")
                    )
                } else if drawer.filteredItems.isEmpty {
                    ContentUnavailableView.search(text: drawer.query)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(drawer.filteredItems) { item in
                                let isPeekFocused = !isDenMode()
                                DrawerItemView(
                                    focusedDrawerItemID: $focusedDrawerItemID,
                                    item: item,
                                    isSelected: drawer.selectedItemID == item.id,
                                    isExpanded: drawer.expandedItemID == item.id,
                                    isPeekVisible: isDrawerOpen()
                                        && drawer.expandedItemID == item.id,
                                    profileColor: profileColor,
                                    peekHeight: peekHeight,
                                    onToggle: { drawer.toggleItem(item.id) },
                                    onPlaceFromContextMenu: { placeFromContextMenu(item.id) },
                                    onPlaceAsBoard: { placeAsBoard(item.id) },
                                    onDiscard: { drawer.discardItem(item.id) },
                                    peek: {
                                        peek(item, isPeekFocused)
                                    }
                                )
                                .id(drawerItemScrollID(for: item.id))
                            }
                        }
                        .padding(.horizontal, DenLayout.outerInset)
                        .padding(.bottom, DenLayout.outerInset)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: drawer.expandedItemID) { _, itemID in
                guard isDrawerOpen(), let itemID else { return }
                schedulePeekScroll(to: itemID, using: proxy)
            }
            .onChange(of: isDrawerOpen()) { _, isOpen in
                guard isOpen, let itemID = drawer.expandedItemID else { return }
                schedulePeekScroll(to: itemID, using: proxy)
            }
        }
    }

    private func schedulePeekScroll(to itemID: UUID, using proxy: ScrollViewProxy) {
        let animation = DenMotion.spatial(reduceMotion: shouldReduceMotion)
        Task { @MainActor in
            await Task.yield()
            guard isDrawerOpen(), drawer.expandedItemID == itemID else { return }
            withAnimation(animation) {
                proxy.scrollTo(drawerItemScrollID(for: itemID), anchor: .top)
            }
        }
    }

    private func drawerItemScrollID(for itemID: UUID) -> String {
        "drawer-item-\(itemID.uuidString)"
    }

    private var isBottomStyle: Bool {
        drawer.isBottomStyle
    }

    private var drawerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: DenRadius.large,
            bottomLeadingRadius: isBottomStyle ? 0 : DenRadius.large,
            bottomTrailingRadius: isBottomStyle ? 0 : DenRadius.large,
            topTrailingRadius: DenRadius.large,
            style: .continuous
        )
    }

    private var shadowY: CGFloat {
        isBottomStyle ? -12 : 12
    }

    private var drawerWidth: CGFloat {
        if isBottomStyle {
            return availableWidth - DenLayout.outerInset * 2
        }
        return min(availableWidth - DenLayout.overlayInset * 2, DenDrawerLayout.floatingWidth)
    }

    private var drawerHeight: CGFloat {
        if isBottomStyle {
            return max(
                DenDrawerLayout.bottomMinimumHeight,
                availableHeight - DenDrawerLayout.windowClearance(shouldShowHeader: shouldShowHeader)
            )
        }
        let preferredHeight: CGFloat
        if drawer.items.isEmpty {
            preferredHeight = DenDrawerLayout.emptyHeight
        } else if drawer.expandedItemID != nil {
            preferredHeight = DenDrawerLayout.floatingExpandedHeight
        } else {
            preferredHeight = DenDrawerLayout.floatingHeight
        }
        return min(availableHeight - DenLayout.overlayInset * 2, preferredHeight)
    }

    private var peekHeight: CGFloat {
        if isBottomStyle {
            return max(DenDrawerLayout.bottomMinimumHeight, drawerHeight - DenDrawerLayout.peekReservedHeight)
        }
        return max(240, drawerHeight - DenDrawerLayout.peekReservedHeight)
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    private func restoreKeyboardFocus() {
        guard !drawer.isFilterInputActive else { return }
        if !isDenMode(), drawer.expandedItemID != nil {
            return
        }
        focusedDrawerItemID = drawer.selectedItemID
    }
}

enum DenDrawerLayout {
    static let headerHorizontalPadding: CGFloat = 16
    static let searchFieldWidth: CGFloat = 300
    static let itemHeight: CGFloat = 46
    static let itemButtonWidth: CGFloat = 28
    static let floatingWidth: CGFloat = 680
    static let floatingHeight: CGFloat = 480
    static let floatingExpandedHeight: CGFloat = 620
    static let emptyHeight: CGFloat = 300
    static let bottomMinimumHeight: CGFloat = 360
    static let peekReservedHeight: CGFloat = 160

    static func windowClearance(shouldShowHeader: Bool) -> CGFloat {
        let topInset = shouldShowHeader ? DenLayout.denHeaderHeight : DenLayout.outerInset
        return topInset + DenLayout.boardHeaderHeight
    }
}
