import SFSafeSymbols
import SwiftUI

struct ZmxIcon: View {
    let size: CGFloat

    var body: some View {
        Image(systemSymbol: .appleTerminalOnRectangle)
            .font(.system(size: size * 0.76))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
