import SFSafeSymbols
import SwiftUI

public struct DenCloseButton: View {
    let label: String
    let action: () -> Void

    public init(label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: some View {
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
