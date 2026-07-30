import SwiftUI
import WebKit

struct DrawerView: View {
    @Environment(DenStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let availableHeight: CGFloat
    let profileColor: Color

    @FocusState private var isSearchFocused: Bool

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
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                HStack(spacing: 6) {
                    Text("Drawer")
                        .font(.title3.bold())
                    Text(itemCountLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button {
                        store.closeDrawer()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Close Drawer")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(store.isDrawerFilterMode ? .primary : .secondary)
                TextField(
                    "Search Drawer Items (/)",
                    text: Binding(
                        get: { store.drawerQuery },
                        set: { store.setDrawerQuery($0) }
                    )
                )
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .disabled(!store.isDrawerFilterMode)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: DenDrawerLayout.searchFieldWidth)
            .background(
                Color.primary.opacity(store.isDrawerFilterMode ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                    .stroke(
                        store.isDrawerFilterMode
                            ? profileColor.opacity(0.86)
                            : Color.primary.opacity(0.10),
                        lineWidth: store.isDrawerFilterMode ? 1.5 : 1
                    )
            }
            .onTapGesture {
                if !store.isDrawerFilterMode {
                    store.enterDrawerFilterMode()
                }
            }
        }
        .padding(.horizontal, DenDrawerLayout.headerHorizontalPadding)
        .padding(.vertical, 12)
        .onChange(of: store.isDrawerFilterMode) { _, newValue in
            isSearchFocused = newValue
        }
    }

    private var drawerContents: some View {
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
                        .foregroundStyle(.secondary)
                        .frame(
                            width: DenDrawerLayout.itemButtonWidth,
                            height: DenDrawerLayout.itemHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard \(item.displayName)")
                .help("Discard")
            }

            if store.isDrawerOpen, store.expandedDrawerItemID == item.id {
                let runtime = store.drawerRuntime(for: item)
                DrawerWebView(webView: runtime.webView)
                    .frame(height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous))
                    .padding([.horizontal, .bottom], DenLayout.outerInset)
            }
        }
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
                        ? profileColor.opacity(0.38)
                        : Color.primary.opacity(0.08)
                )
        }
    }

    private var drawerHeight: CGFloat {
        max(DenDrawerLayout.minimumHeight, availableHeight - DenDrawerLayout.windowClearance)
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

    private var itemCountLabel: String {
        let total = store.state.drawerItems.count
        guard !store.drawerQuery.isEmpty else { return "\(total)" }
        return "\(store.filteredDrawerItems.count) of \(total)"
    }
}

private enum DenDrawerLayout {
    static let headerHorizontalPadding: CGFloat = 14
    static let searchFieldWidth: CGFloat = 320
    static let itemHeight: CGFloat = 46
    static let itemButtonWidth: CGFloat = 28
    static let minimumHeight: CGFloat = 360
    static let windowClearance: CGFloat = 52
    static let previewReservedHeight: CGFloat = 160
}

private struct DrawerWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        DispatchQueue.main.async { [weak webView] in
            guard let webView else { return }
            webView.window?.makeFirstResponder(webView)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
