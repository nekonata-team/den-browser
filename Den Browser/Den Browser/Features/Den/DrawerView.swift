import SwiftUI
import WebKit

struct DrawerView: View {
    @Environment(DenStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let availableHeight: CGFloat
    let profileColor: Color

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
        ZStack {
            Text("Drawer")
                .font(.title3.bold())

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
        .padding(.horizontal, DenDrawerLayout.headerHorizontalPadding)
        .frame(height: DenDrawerLayout.headerHeight)
    }

    private var drawerContents: some View {
        Group {
            if store.state.drawerItems.isEmpty {
                ContentUnavailableView(
                    "Drawer is empty",
                    systemImage: "tray",
                    description: Text("Keep a Current Sheet here before its work context is settled.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.state.drawerItems) { item in
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
                                .lineLimit(1)

                            Text(item.url.host(percentEncoded: false) ?? item.url.absoluteString)
                                .font(.caption)
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

                Button(role: .destructive) {
                    store.discardDrawerItem(item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(
                            width: DenDrawerLayout.discardButtonWidth,
                            height: DenDrawerLayout.itemHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard \(item.displayName)")
                .help("Discard")
            }

            if store.expandedDrawerItemID == item.id {
                let runtime = store.drawerRuntime(for: item)
                DrawerWebView(webView: runtime.webView)
                    .frame(height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous))
                    .padding([.horizontal, .bottom], DenLayout.outerInset)
            }

            Divider()
        }
        .background(
            store.selectedDrawerItemID == item.id
                ? profileColor.opacity(0.18)
                : Color.clear
        )
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
}

private enum DenDrawerLayout {
    static let headerHeight: CGFloat = 58
    static let headerHorizontalPadding: CGFloat = 14
    static let itemHeight: CGFloat = 52
    static let discardButtonWidth: CGFloat = 32
    static let minimumHeight: CGFloat = 360
    static let windowClearance: CGFloat = 72
    static let previewReservedHeight: CGFloat = 160
}

private struct DrawerWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
