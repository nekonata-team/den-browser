import SwiftUI
import WebKit

struct DrawerView: View {
    @Environment(DenStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let availableHeight: CGFloat
    let profileColor: Color
    var shouldShowHeader: Bool = true

    @FocusState private var isSearchFocused: Bool
    @FocusState private var focusedDrawerItemID: UUID?
    @State private var hoveredDiscardItemID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            drawerContents
        }
        .frame(maxWidth: .infinity)
        .frame(height: drawerHeight, alignment: .top)
        .background(.regularMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: DenRadius.large,
                topTrailingRadius: DenRadius.large,
                style: .continuous
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: DenRadius.large,
                topTrailingRadius: DenRadius.large,
                style: .continuous
            )
            .strokeBorder(Color.primary.opacity(0.14))
        }
        .shadow(color: .black.opacity(0.4), radius: 28, y: -12)
        .animation(DenMotion.feedback(reduceMotion: shouldReduceMotion), value: store.expandedDrawerItemID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer")
        .onAppear {
            restoreKeyboardFocus()
        }
        .onChange(of: store.isDenMode) { _, _ in
            restoreKeyboardFocus()
        }
        .onChange(of: store.selectedDrawerItemID) { _, itemID in
            if store.isDenMode, !store.isDrawerFilterInputActive {
                focusedDrawerItemID = itemID
            }
        }
        .onChange(of: store.expandedDrawerItemID) { _, _ in
            restoreKeyboardFocus()
        }
    }

    private var header: some View {
        VStack(spacing: isSearchPresented ? 10 : 0) {
            ZStack {
                HStack(spacing: 6) {
                    Text("Drawer")
                        .font(.title3.bold())
                    Text(itemCountLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button(role: .destructive) {
                        store.requestDrawerClearConfirmation()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.state.drawerItems.isEmpty)
                    .accessibilityLabel("Discard All Drawer Items")
                    .help("Discard All Drawer Items")

                    Button {
                        store.enterDrawerFilterMode()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search Drawer Items")
                    .help("Search Drawer Items (/)")

                    DenCloseButton(label: "Close Drawer") {
                        store.closeDrawer()
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(store.isDrawerFilterInputActive ? .primary : .secondary)
                    .accessibilityHidden(true)
                TextField(
                    text: Binding(
                        get: { store.drawerQuery },
                        set: { store.setDrawerQuery($0) }
                    ),
                    prompt: Text("Search drawer items")
                ) {
                    Text("Search Drawer Items")
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .disabled(!store.isDrawerFilterInputActive)
                .accessibilityIdentifier("drawer-search")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: DenDrawerLayout.searchFieldWidth)
            .background(
                Color.primary.opacity(store.isDrawerFilterInputActive ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                    .stroke(
                        store.isDrawerFilterInputActive
                            ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.86))
                            : Color.primary.opacity(0.10),
                        lineWidth: store.isDrawerFilterInputActive ? 1.5 : 1
                    )
            }
            .opacity(isSearchPresented ? 1 : 0)
            .frame(height: isSearchPresented ? nil : 0)
            .clipped()
            .allowsHitTesting(isSearchPresented)
            .accessibilityHidden(!isSearchPresented)
            .onTapGesture {
                if !store.isDrawerFilterInputActive {
                    store.enterDrawerFilterMode()
                }
            }
        }
        .padding(.horizontal, DenDrawerLayout.headerHorizontalPadding)
        .padding(.vertical, 12)
        .onChange(of: store.isDrawerFilterInputActive) { _, newValue in
            if newValue {
                isSearchFocused = true
            } else {
                restoreKeyboardFocus()
            }
        }
    }

    private var drawerContents: some View {
        ScrollViewReader { proxy in
            Group {
                if store.state.drawerItems.isEmpty {
                    ContentUnavailableView(
                        "Drawer is empty",
                        systemImage: "tray",
                        description: Text("Keep a Current Sheet here before its work context is settled.")
                    )
                } else if store.filteredDrawerItems.isEmpty {
                    ContentUnavailableView.search(text: store.drawerQuery)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(store.filteredDrawerItems) { item in
                                drawerSection(item)
                            }
                        }
                        .padding(.horizontal, DenLayout.outerInset)
                        .padding(.bottom, DenLayout.outerInset)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: store.expandedDrawerItemID) { _, itemID in
                guard store.isDrawerOpen, let itemID else { return }
                schedulePreviewScroll(to: itemID, using: proxy)
            }
            .onChange(of: store.isDrawerOpen) { _, isOpen in
                guard isOpen, let itemID = store.expandedDrawerItemID else { return }
                schedulePreviewScroll(to: itemID, using: proxy)
            }
        }
    }

    private func drawerSection(_ item: DrawerItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    store.toggleDrawerItem(item.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.callout)
                                .lineLimit(1)

                            Text(item.url.host(percentEncoded: false) ?? item.url.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        Image(
                            systemName: store.expandedDrawerItemID == item.id
                                ? "chevron.down"
                                : "chevron.right"
                        )
                        .font(.caption)
                        .frame(width: 12)
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, minHeight: DenDrawerLayout.itemHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focused($focusedDrawerItemID, equals: item.id)
                .contextMenu {
                    Button("Place as Board") {
                        store.placeDrawerItemAsBoard(item.id)
                    }
                    Button("Discard", role: .destructive) {
                        store.discardDrawerItem(item.id)
                    }
                }
                .accessibilityAddTraits(store.selectedDrawerItemID == item.id ? .isSelected : [])

                Button {
                    store.placeDrawerItemAsBoard(item.id)
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .foregroundStyle(.primary)
                        .frame(
                            width: DenDrawerLayout.itemButtonWidth,
                            height: DenDrawerLayout.itemHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Place \(item.displayName) as Board")
                .help("Place as Board")

                Button(role: .destructive) {
                    store.discardDrawerItem(item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(hoveredDiscardItemID == item.id ? .red : .primary)
                        .frame(
                            width: DenDrawerLayout.itemButtonWidth,
                            height: DenDrawerLayout.itemHeight)
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredDiscardItemID = isHovering ? item.id : nil
                }
                .accessibilityLabel("Discard \(item.displayName)")
                .help("Discard")
            }

            if store.isDrawerOpen, store.expandedDrawerItemID == item.id {
                let runtime = store.drawerRuntime(for: item)
                DrawerWebView(
                    webView: runtime.webView,
                    isFocused: !store.isDenMode
                )
                .id(item.id)
                .frame(height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous))
                .padding([.horizontal, .bottom], DenLayout.outerInset)
            }
        }
        .id(drawerItemScrollID(for: item.id))
        .background(
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .fill(
                    store.selectedDrawerItemID == item.id
                        ? profileColor.opacity(0.18)
                        : Color.primary.opacity(0.04)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .stroke(
                    store.selectedDrawerItemID == item.id
                        ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.38))
                        : Color.primary.opacity(0.08)
                )
        }
    }

    private func schedulePreviewScroll(to itemID: UUID, using proxy: ScrollViewProxy) {
        let animation = DenMotion.spatial(reduceMotion: shouldReduceMotion)
        Task { @MainActor in
            await Task.yield()
            guard store.isDrawerOpen, store.expandedDrawerItemID == itemID else { return }
            withAnimation(animation) {
                proxy.scrollTo(drawerItemScrollID(for: itemID), anchor: .top)
            }
        }
    }

    private func drawerItemScrollID(for itemID: UUID) -> String {
        "drawer-item-\(itemID.uuidString)"
    }

    private var drawerHeight: CGFloat {
        max(
            DenDrawerLayout.minimumHeight,
            availableHeight - DenDrawerLayout.windowClearance(shouldShowHeader: shouldShowHeader)
        )
    }

    private var previewHeight: CGFloat {
        max(DenDrawerLayout.minimumHeight, drawerHeight - DenDrawerLayout.previewReservedHeight)
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: store.preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }

    private var isSearchPresented: Bool {
        store.isDrawerFilterPresented || !store.drawerQuery.isEmpty
    }

    private var itemCountLabel: String {
        let total = store.state.drawerItems.count
        guard !store.drawerQuery.isEmpty else { return "\(total)" }
        return "\(store.filteredDrawerItems.count) of \(total)"
    }

    private func restoreKeyboardFocus() {
        guard !store.isDrawerFilterInputActive else { return }
        if !store.isDenMode, store.expandedDrawerItemID != nil {
            return
        }
        focusedDrawerItemID = store.selectedDrawerItemID
    }
}

private enum DenDrawerLayout {
    static let headerHorizontalPadding: CGFloat = 14
    static let searchFieldWidth: CGFloat = 320
    static let itemHeight: CGFloat = 46
    static let itemButtonWidth: CGFloat = 28
    static let minimumHeight: CGFloat = 360
    static let previewReservedHeight: CGFloat = 160

    static func windowClearance(shouldShowHeader: Bool) -> CGFloat {
        let topInset = shouldShowHeader ? DenLayout.denHeaderHeight : DenLayout.outerInset
        return topInset + DenLayout.boardHeaderHeight
    }
}

private struct DrawerWebView: NSViewRepresentable {
    let webView: WKWebView
    let isFocused: Bool

    func makeNSView(context: Context) -> SurfaceHost<Bool, WKWebView> {
        let host = SurfaceHost<Bool, WKWebView>(content: webView)
        update(host)
        return host
    }

    func updateNSView(_ nsView: SurfaceHost<Bool, WKWebView>, context: Context) {
        update(nsView)
    }

    private func update(_ host: SurfaceHost<Bool, WKWebView>) {
        host.update(request: isFocused ? true : nil) { window in
            guard needsFirstResponderActivation(window.firstResponder, target: webView) else {
                return true
            }
            return window.makeFirstResponder(webView)
        }
    }
}
