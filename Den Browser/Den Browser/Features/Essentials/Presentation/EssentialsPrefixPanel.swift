import DenDomain
import SFSafeSymbols
import SwiftUI

struct EssentialsPrefixPanel: View {
    let profileColor: Color

    @Environment(DenStore.self) private var store
    @Environment(DenViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .sparkles) {
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
                ViewThatFits(in: .vertical) {
                    essentialRows
                        .fixedSize(horizontal: false, vertical: true)
                    ScrollViewReader { proxy in
                        ScrollView {
                            essentialRows
                        }
                        .onAppear { scrollToSelectedEssential(using: proxy) }
                        .onChange(of: viewModel.selectedEssentialID) { _, _ in
                            scrollToSelectedEssential(using: proxy)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            DenPanelHint(
                store.essentials.isEmpty
                    ? "Press Escape to cancel"
                    : "↑↓ Focus · Return Start · Essential key Start · Esc Cancel"
            )
        }
        .denPanel(width: DenPanelLayout.narrowWidth)
    }

    private var essentialRows: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.controlSpacing) {
            ForEach(store.essentials) { essential in
                let isSelected = essential.id == viewModel.selectedEssentialID
                HStack(spacing: DenPanelLayout.controlSpacing) {
                    ShortcutChip(tokens: [essential.displayKey], width: 42)
                    Text(essential.name)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 36)
                .denSelectionHighlight(isSelected, profileColor: profileColor, inactiveOpacity: 0.04)
                .contentShape(RoundedRectangle(cornerRadius: DenRadius.small))
                .onTapGesture { viewModel.selectEssential(essential.id) }
                .id(essential.id)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint("Return starts this Essential. Its shortcut starts it directly.")
            }
        }
    }

    private func scrollToSelectedEssential(using proxy: ScrollViewProxy) {
        guard let selectedEssentialID = viewModel.selectedEssentialID else { return }
        proxy.scrollTo(selectedEssentialID, anchor: .center)
    }
}
