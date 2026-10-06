import SFSafeSymbols
import SwiftUI

struct DenCloseButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemSymbol: .xmark)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .contentShape(Circle())
        .accessibilityLabel(label)
    }
}
