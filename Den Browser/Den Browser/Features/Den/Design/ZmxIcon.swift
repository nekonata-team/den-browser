import SFSafeSymbols
import SwiftUI

struct ZmxIcon: View {
    let size: CGFloat

    var body: some View {
        Image(systemSymbol: .appleTerminal)
            .font(.system(size: size * 0.76))
            .overlay(alignment: .bottomTrailing) {
                Image(systemSymbol: .arrowClockwise)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(size * 0.04)
                    .background(.background, in: Circle())
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
