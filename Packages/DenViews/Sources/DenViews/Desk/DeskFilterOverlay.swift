import DenModels
import SFSafeSymbols
import SwiftUI

public struct DeskFilterOverlay: View {
    @Environment(DeskFilterModel.self) private var deskFilter
    @Environment(AppearanceModel.self) private var preferences
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let profileColor: Color
    @FocusState private var isFocused: Bool

    public init(profileColor: Color) { self.profileColor = profileColor }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: .magnifyingglass)
                .foregroundStyle(deskFilter.isInputActive ? .primary : .secondary)
                .accessibilityHidden(true)

            TextField(
                text: Binding(
                    get: { deskFilter.query },
                    set: { deskFilter.setQuery($0) }
                ),
                prompt: Text("Filter boards")
            ) {
                Text("Filter Boards")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($isFocused)
            .disabled(!deskFilter.isInputActive)
            .accessibilityIdentifier("desk-filter-input")

            Text("\(deskFilter.filteredBoards.count)/\(deskFilter.totalBoardCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: DenLayout.deskFilterWidth)
        .glassEffect(in: RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DenRadius.medium, style: .continuous)
                .stroke(
                    deskFilter.isInputActive
                        ? (differentiateWithoutColor
                            ? Color.primary : profileColor.opacity(DenSurfaceColors.emphasisOpacity))
                        : Color.primary.opacity(0.16),
                    lineWidth: deskFilter.isInputActive ? 1.5 : 1
                )
        }
        .padding(.top, DenLayout.outerInset)
        .transition(DenMotion.panelTransition(reduceMotion: shouldReduceMotion))
        .onTapGesture {
            deskFilter.enter()
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = deskFilter.isInputActive
            }
        }
        .onChange(of: deskFilter.isInputActive) { _, isActive in
            isFocused = isActive
        }
        .onChange(of: deskFilter.query) { _, newValue in
            if isFocused {
                TextInputComposition.syncActiveFieldEditor(to: newValue)
            }
        }
        .accessibilityIdentifier("desk-filter")
    }

    private var shouldReduceMotion: Bool {
        DenMotion.shouldReduceMotion(
            preference: preferences.motionPreference,
            systemReduceMotion: systemReduceMotion
        )
    }
}
