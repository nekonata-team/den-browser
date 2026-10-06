import DenDesign
import DenDomain
import SFSafeSymbols
import SwiftUI

struct DrawerItemView: View {
    @Environment(DenStore.self) private var store
    @Environment(DenViewModel.self) private var viewModel
    @Environment(DrawerViewModel.self) private var drawer
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    @FocusState.Binding var focusedDrawerItemID: UUID?
    @State private var isDiscardHovered = false

    let item: DrawerItem
    let profileColor: Color
    let previewHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    drawer.toggleItem(item.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemSymbol: .link)
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
                            systemSymbol: drawer.expandedItemID == item.id
                                ? .chevronDown
                                : .chevronRight
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
                .accessibilityAddTraits(drawer.selectedItemID == item.id ? .isSelected : [])

                Button {
                    viewModel.placeDrawerItemAsBoard(item.id)
                } label: {
                    Image(systemSymbol: .rectangleStackBadgePlus)
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
                    Image(systemSymbol: .trash)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isDiscardHovered ? .red : .primary)
                        .frame(
                            width: DenDrawerLayout.itemButtonWidth,
                            height: DenDrawerLayout.itemHeight)
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    isDiscardHovered = isHovering
                }
                .accessibilityLabel("Discard \(item.displayName)")
                .help("Discard")
            }

            if viewModel.isDrawerOpen, drawer.expandedItemID == item.id {
                let runtime = store.drawerRuntime(for: item)
                DrawerWebSurface(
                    webView: runtime.webView,
                    isFocused: !viewModel.isDenMode
                )
                .id(item.id)
                .frame(height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: DenRadius.small, style: .continuous))
                .padding([.horizontal, .bottom], DenLayout.outerInset)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .fill(
                    drawer.selectedItemID == item.id
                        ? (differentiateWithoutColor ? Color.primary : profileColor).opacity(0.18)
                        : Color.primary.opacity(0.04)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .stroke(
                    drawer.selectedItemID == item.id
                        ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.38))
                        : Color.primary.opacity(0.08)
                )
        }
    }
}
