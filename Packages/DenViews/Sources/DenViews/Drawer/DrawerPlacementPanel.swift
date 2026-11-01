import DenDomain
import DenModels
import SwiftUI

public struct DrawerPlacementPanel: View {
    @Environment(DenWindowModel.self) private var windowModel
    private let profileColor: Color

    public init(profileColor: Color) {
        self.profileColor = profileColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            Text("Place in Desk").font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(windowModel.desks.desks.enumerated()), id: \.element.id) { index, desk in
                            let available = windowModel.desks.canSelectDesk(desk.id)
                            Button {
                                windowModel.drawer.placementDeskID = desk.id
                                windowModel.confirmDrawerPlacementDesk()
                            } label: {
                                HStack {
                                    Text(index == 9 ? "0" : "\(index + 1)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, alignment: .leading)
                                    Text(desk.label).lineLimit(1)
                                    Spacer()
                                    if !available { Text("Open in another window").foregroundStyle(.secondary) }
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .denSelectionHighlight(
                                    desk.id == windowModel.drawer.placementDeskID, profileColor: profileColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(!available)
                            .accessibilityAddTraits(desk.id == windowModel.drawer.placementDeskID ? .isSelected : [])
                            .id(desk.id)
                        }
                    }
                }
                .frame(
                    height: min(
                        CGFloat(windowModel.desks.desks.count) * 30
                            + CGFloat(max(0, windowModel.desks.desks.count - 1)) * 4,
                        DenPanelLayout.standardListMaxHeight)
                )
                .onAppear {
                    if let id = windowModel.drawer.placementDeskID { proxy.scrollTo(id) }
                }
                .onChange(of: windowModel.drawer.placementDeskID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            DenPanelHint("1–9 / 0 Place · ↑↓ Select · Return Place · Escape Cancel")
        }
        .denPanel()
        .accessibilityIdentifier("drawer-placement-desk-picker")
    }
}
