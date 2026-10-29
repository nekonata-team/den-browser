import AppKit
import DenDomain
import SFSafeSymbols
import SwiftUI

public struct EssentialsPrefixPanel: View {
    public let profileColor: Color
    public let essentials: [Essential]
    public let selectedEssentialID: UUID?
    public let onSelect: (UUID) -> Void
    public let onOpenInDrawer: (UUID) -> Void

    public init(
        profileColor: Color, essentials: [Essential], selectedEssentialID: UUID? = nil,
        onSelect: @escaping (UUID) -> Void, onOpenInDrawer: @escaping (UUID) -> Void
    ) {
        self.profileColor = profileColor
        self.essentials = essentials
        self.selectedEssentialID = selectedEssentialID
        self.onSelect = onSelect
        self.onOpenInDrawer = onOpenInDrawer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .sparkles) {
                Text("Essentials")
                    .font(.headline)
            }

            if essentials.isEmpty {
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
                        .onChange(of: selectedEssentialID) { _, _ in
                            scrollToSelectedEssential(using: proxy)
                        }
                    }
                }
                .frame(maxHeight: DenPanelLayout.standardListMaxHeight)
            }

            DenPanelHint(
                essentials.isEmpty
                    ? "Press Escape to cancel"
                    : "↑↓ Focus · Return Start · ⌥Return / ⌥Click Drawer · Essential key Start · Esc Cancel"
            )
        }
        .denPanel()
    }

    private var essentialRows: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.controlSpacing) {
            ForEach(essentials) { essential in
                let isSelected = essential.id == selectedEssentialID
                HStack(spacing: DenPanelLayout.controlSpacing) {
                    ShortcutChip(tokens: [essential.displayKey], width: 42)
                    Text(essential.name)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 36)
                .denSelectionHighlight(isSelected, profileColor: profileColor, showsInactiveBackground: true)
                .contentShape(RoundedRectangle(cornerRadius: DenRadius.small))
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.option) {
                        onOpenInDrawer(essential.id)
                    } else {
                        onSelect(essential.id)
                    }
                }
                .id(essential.id)
                .accessibilityIdentifier("essential.\(essential.id.uuidString)")
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(
                    "Return starts this Essential. Option Return or Option click opens a URL, search, or Terminal command in Drawer. Its shortcut starts it directly."
                )
            }
        }
    }

    private func scrollToSelectedEssential(using proxy: ScrollViewProxy) {
        guard let selectedEssentialID else { return }
        proxy.scrollTo(selectedEssentialID, anchor: .center)
    }
}
