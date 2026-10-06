import DenDesign
import DenDomain
import SFSafeSymbols
import SwiftUI

struct DrawerHeaderView: View {
    @Environment(DenStore.self) private var store
    @Environment(DenViewModel.self) private var viewModel
    @Environment(DrawerViewModel.self) private var drawer
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    @FocusState.Binding var isSearchFocused: Bool

    let profileColor: Color
    let isBottomStyle: Bool

    var body: some View {
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
                        Image(systemSymbol: .trash)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.state.drawerItems.isEmpty)
                    .accessibilityLabel("Discard All Drawer Items")
                    .help("Discard All Drawer Items")

                    Button {
                        drawer.enterFilterMode()
                    } label: {
                        Image(systemSymbol: .magnifyingglass)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search Drawer Items")
                    .help("Search Drawer Items (/)")

                    Button {
                        drawer.toggleStyle()
                    } label: {
                        Image(
                            systemSymbol: isBottomStyle
                                ? .arrowDownRightAndArrowUpLeft
                                : .arrowUpLeftAndArrowDownRight
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isBottomStyle ? "Contract Drawer (f)" : "Expand Drawer (f)")
                    .help(isBottomStyle ? "Contract Drawer (f)" : "Expand Drawer (f)")

                    DenCloseButton(label: "Close Drawer") {
                        viewModel.closeDrawer()
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemSymbol: .magnifyingglass)
                    .foregroundStyle(drawer.isFilterInputActive ? .primary : .secondary)
                    .accessibilityHidden(true)
                TextField(
                    text: Binding(
                        get: { drawer.query },
                        set: { drawer.setQuery($0) }
                    ),
                    prompt: Text("Search drawer items")
                ) {
                    Text("Search Drawer Items")
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .disabled(!drawer.isFilterInputActive)
                .accessibilityIdentifier("drawer-search")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: DenDrawerLayout.searchFieldWidth)
            .background(
                Color.primary.opacity(drawer.isFilterInputActive ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                    .stroke(
                        drawer.isFilterInputActive
                            ? (differentiateWithoutColor ? Color.primary : profileColor.opacity(0.86))
                            : Color.primary.opacity(0.10),
                        lineWidth: drawer.isFilterInputActive ? 1.5 : 1
                    )
            }
            .opacity(isSearchPresented ? 1 : 0)
            .frame(height: isSearchPresented ? nil : 0)
            .clipped()
            .allowsHitTesting(isSearchPresented)
            .accessibilityHidden(!isSearchPresented)
            .onTapGesture {
                if !drawer.isFilterInputActive {
                    drawer.enterFilterMode()
                }
            }
        }
        .padding(.horizontal, DenDrawerLayout.headerHorizontalPadding)
        .padding(.vertical, 12)
    }

    private var isSearchPresented: Bool {
        drawer.isFilterPresented || !drawer.query.isEmpty
    }

    private var itemCountLabel: String {
        let total = store.state.drawerItems.count
        guard !drawer.query.isEmpty else { return "\(total)" }
        return "\(drawer.filteredItems.count) of \(total)"
    }
}
