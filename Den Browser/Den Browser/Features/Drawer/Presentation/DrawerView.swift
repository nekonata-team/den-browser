import DenDesign
import DenDomain
import SFSafeSymbols
import SwiftUI

struct DrawerView: View {
    @Environment(DenStore.self) private var store
    @Environment(DenViewModel.self) private var viewModel
    @Environment(DrawerViewModel.self) private var drawer
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let availableHeight: CGFloat
    let availableWidth: CGFloat
    let profileColor: Color
    var shouldShowHeader: Bool = true

    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedDrawerItemID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            drawerContents
        }
        .frame(width: drawerWidth, height: drawerHeight, alignment: .top)
        .background(.regularMaterial)
        .clipShape(drawerShape)
        .overlay {
            drawerShape
                .strokeBorder(Color.primary.opacity(0.14))
        }
        .shadow(color: .black.opacity(isBottomStyle ? 0.4 : 0.35), radius: 28, y: shadowY)
        .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: drawer.expandedItemID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer")
        .onAppear {
            restoreKeyboardFocus()
        }
        .onChange(of: viewModel.isDenMode) { _, _ in
            restoreKeyboardFocus()
        }
        .onChange(of: drawer.selectedItemID) { _, itemID in
            if viewModel.isDenMode, !drawer.isFilterInputActive {
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
                if store.state.drawerItems.isEmpty {
                    ContentUnavailableView(
                        "Drawer is empty",
                        systemSymbol: .tray,
                        description: Text("Keep a Current Sheet here before its work context is settled.")
                    )
                } else if drawer.filteredItems.isEmpty {
                    ContentUnavailableView.search(text: drawer.query)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(drawer.filteredItems) { item in
                                let isPreviewFocused = !viewModel.isDenMode
                                DrawerItemView(
                                    focusedDrawerItemID: $focusedDrawerItemID,
                                    item: item,
                                    isSelected: drawer.selectedItemID == item.id,
                                    isExpanded: drawer.expandedItemID == item.id,
                                    isPreviewVisible: viewModel.isDrawerOpen
                                        && drawer.expandedItemID == item.id,
                                    profileColor: profileColor,
                                    previewHeight: previewHeight,
                                    onToggle: { drawer.toggleItem(item.id) },
                                    onPlaceFromContextMenu: { store.placeDrawerItemAsBoard(item.id) },
                                    onPlaceAsBoard: { viewModel.placeDrawerItemAsBoard(item.id) },
                                    onDiscard: { store.discardDrawerItem(item.id) },
                                    preview: {
                                        let runtime = store.drawerRuntime(for: item)
                                        DrawerWebSurface(
                                            webView: runtime.webView,
                                            isFocused: isPreviewFocused
                                        )
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
                guard viewModel.isDrawerOpen, let itemID else { return }
                schedulePreviewScroll(to: itemID, using: proxy)
            }
            .onChange(of: viewModel.isDrawerOpen) { _, isOpen in
                guard isOpen, let itemID = drawer.expandedItemID else { return }
                schedulePreviewScroll(to: itemID, using: proxy)
            }
        }
    }

    private func schedulePreviewScroll(to itemID: UUID, using proxy: ScrollViewProxy) {
        let animation = DenMotion.spatial(reduceMotion: shouldReduceMotion)
        Task { @MainActor in
            await Task.yield()
            guard viewModel.isDrawerOpen, drawer.expandedItemID == itemID else { return }
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
        if store.state.drawerItems.isEmpty {
            preferredHeight = DenDrawerLayout.emptyHeight
        } else if drawer.expandedItemID != nil {
            preferredHeight = DenDrawerLayout.floatingExpandedHeight
        } else {
            preferredHeight = DenDrawerLayout.floatingHeight
        }
        return min(availableHeight - DenLayout.overlayInset * 2, preferredHeight)
    }

    private var previewHeight: CGFloat {
        if isBottomStyle {
            return max(DenDrawerLayout.bottomMinimumHeight, drawerHeight - DenDrawerLayout.previewReservedHeight)
        }
        return max(240, drawerHeight - DenDrawerLayout.previewReservedHeight)
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: store.preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    private func restoreKeyboardFocus() {
        guard !drawer.isFilterInputActive else { return }
        if !viewModel.isDenMode, drawer.expandedItemID != nil {
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
    static let previewReservedHeight: CGFloat = 160

    static func windowClearance(shouldShowHeader: Bool) -> CGFloat {
        let topInset = shouldShowHeader ? DenLayout.denHeaderHeight : DenLayout.outerInset
        return topInset + DenLayout.boardHeaderHeight
    }
}
