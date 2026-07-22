import SwiftUI

struct OpenBoardPanel: View {
    @Binding var urlText: String
    @FocusState.Binding var isFocused: Bool

    let defaultBoardWidth: Double
    let onSubmit: (Double) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .foregroundStyle(.secondary)

                TextField("Open URL or search", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isFocused)
                    .onSubmit { onSubmit(defaultBoardWidth) }
            }
            .frame(height: 38)

            HStack(spacing: 12) {
                Text("New board opens to the right of the focused board")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("n in Den Mode")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand(perform: onDismiss)
    }
}
