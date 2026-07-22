import SwiftUI

struct RenameDeskPanel: View {
    @Environment(DenStore.self) private var store
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "pencil").foregroundStyle(.secondary)
                TextField("Rename desk", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .focused($isFocused)
                    .onSubmit { store.renameFocusedDesk(to: text) }
            }
            .frame(height: 38)
            HStack(spacing: 12) {
                Text("Press Return to confirm, Escape to cancel").foregroundStyle(.secondary)
                Spacer()
                Text("R in Den Mode").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
        .frame(width: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))
        .onAppear {
            text = store.focusedDesk?.label ?? ""
            DispatchQueue.main.async { isFocused = true }
        }
        .onExitCommand { store.hideRenameDeskPanel() }
    }
}
