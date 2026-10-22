import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

public struct OpenProfilePanel: View {
    let profiles: [ProfileState]
    let profileColor: Color
    let onOpenProfile: (ProfileID) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedProfileID: ProfileID?
    @FocusState private var isFocused: Bool

    public init(
        profiles: [ProfileState], profileColor: Color, onOpenProfile: @escaping (ProfileID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.profiles = profiles
        self.profileColor = profileColor
        self.onOpenProfile = onOpenProfile
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DenPanelLayout.contentSpacing) {
            DenPanelHeader(systemSymbol: .personCropCircle) {
                TextField(
                    text: $query,
                    prompt: Text("Search profiles")
                ) {
                    Text("Open Profile")
                }
                .denPanelHeaderField()
                .focused($isFocused)
                .accessibilityIdentifier("open-profile-input")
                .onKeyPress(.downArrow) {
                    guard !TextInputComposition.isActive else { return .ignored }
                    moveProfileSelection(by: 1)
                    return filteredProfiles.isEmpty ? .ignored : .handled
                }
                .onKeyPress(.upArrow) {
                    guard !TextInputComposition.isActive else { return .ignored }
                    moveProfileSelection(by: -1)
                    return filteredProfiles.isEmpty ? .ignored : .handled
                }
                .onSubmit {
                    TextInputComposition.performUnlessActive(confirmSelection)
                }
            }

            ForEach(filteredProfiles) { profile in
                Button {
                    openProfile(profile.id)
                } label: {
                    HStack(spacing: DenPanelLayout.controlSpacing) {
                        Circle()
                            .fill(profileDisplayColor(for: profile.color))
                            .frame(width: 10, height: 10)
                        Text(profile.name)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 30)
                .denSelectionHighlight(profile.id == selectedProfileID, profileColor: profileColor)
            }

            DenPanelHint("↑↓ Select · Return Open · Escape Close")
        }
        .denPanel()
        .onAppear { DispatchQueue.main.async { isFocused = true } }
        .onChange(of: query) { _, _ in selectedProfileID = nil }
        .onExitCommand(perform: close)
    }

    private var filteredProfiles: [ProfileState] {
        guard !query.isEmpty else { return profiles }
        return profiles.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func moveProfileSelection(by offset: Int) {
        selectedProfileID = SelectionNavigation.next(
            selectedProfileID,
            among: filteredProfiles.map(\.id),
            by: offset
        )
    }

    private func confirmSelection() {
        guard let profileID = selectedProfileID ?? filteredProfiles.first?.id else { return }
        openProfile(profileID)
    }

    private func openProfile(_ profileID: ProfileID) {
        onClose()
        onOpenProfile(profileID)
    }

    private func close() {
        onClose()
    }
}
