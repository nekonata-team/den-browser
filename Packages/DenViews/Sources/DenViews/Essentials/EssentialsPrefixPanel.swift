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
    @State private var opensInDrawer = false
    @State private var listHeight: CGFloat = 0

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
                Spacer()
                if !essentials.isEmpty {
                    Label(
                        opensInDrawer ? "Add to Drawer" : "Open Board",
                        systemSymbol: opensInDrawer ? .tray : .plusRectangle
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if essentials.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No Essentials configured.")
                    Text("Configure Essentials in Settings.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        essentialRows
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.size.height
                            } action: {
                                listHeight = $0
                            }
                    }
                    .frame(height: min(listHeight, DenPanelLayout.standardListMaxHeight))
                    .onChange(of: listHeight) { _, _ in
                        scrollToSelectedEssential(using: proxy)
                    }
                    .onChange(of: selectedEssentialID) { _, _ in
                        scrollToSelectedEssential(using: proxy)
                    }
                }
            }

            if essentials.isEmpty {
                DenPanelHint("Press Escape to cancel")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    DenPanelHint(opensInDrawer ? "⌥Key / ⌥Return Add to Drawer" : "Essential key / Return Open Board")
                    DenPanelHint("↑↓ Select · Hold ⌥ for Drawer · Click Select · ⌥Click Drawer · Esc Cancel")
                }
            }
        }
        .denPanel()
        .onModifierKeysChanged(mask: .option) { _, modifiers in
            opensInDrawer = modifiers.contains(.option)
        }
    }

    private var essentialRows: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.controlSpacing) {
            ForEach(essentials) { essential in
                let isSelected = essential.id == selectedEssentialID
                HStack(spacing: DenPanelLayout.controlSpacing) {
                    Image(systemSymbol: inputSymbol(for: essential))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(essential.name)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .lineLimit(1)
                        Text(essential.input)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    ShortcutChip(tokens: [essential.displayKey], width: 42)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
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
                    "Return or its shortcut opens a Board. Hold Option with Return, its shortcut, or a click to open in Drawer."
                )
            }
        }
    }

    private func inputSymbol(for essential: Essential) -> SFSymbol {
        switch essential.input.split(maxSplits: 1, whereSeparator: \.isWhitespace).first {
        case ":terminal": .appleTerminal
        case ":zellij": .rectangleSplit3x1
        case ":zmx": .appleTerminalOnRectangle
        default: .link
        }
    }

    private func scrollToSelectedEssential(using proxy: ScrollViewProxy) {
        guard let selectedEssentialID else { return }
        proxy.scrollTo(selectedEssentialID, anchor: .center)
    }
}
