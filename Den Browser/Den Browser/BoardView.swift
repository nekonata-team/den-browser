import SwiftUI
import WebKit

struct BoardView: View {
    let board: BoardState
    let isFocused: Bool
    let isHeld: Bool
    let runtime: BoardRuntime
    let height: Double
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .onTapGesture(perform: onFocus)
            BoardWebView(webView: runtime.webView, isFocused: isFocused, onFocus: onFocus)
        }
        .frame(width: board.width, height: height)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: isHeld || isFocused ? 2 : 1)
        }
        .shadow(color: .black.opacity(isHeld ? 0.50 : (isFocused ? 0.42 : 0.30)), radius: isHeld ? 42 : (isFocused ? 34 : 24), x: 0, y: isHeld ? 28 : 22)
        .offset(y: isHeld ? -6 : 0)
    }

    private var borderColor: Color {
        if isHeld {
            return .orange.opacity(0.86)
        }
        if isFocused {
            return .cyan.opacity(0.75)
        }
        return .white.opacity(0.16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(board.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.86))
                    .lineLimit(1)

                Text(hostLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.black.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            SheetStackIndicator(canGoBack: runtime.webView.canGoBack, canGoForward: runtime.webView.canGoForward)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.regularMaterial)
    }

    private var hostLabel: String {
        URL(string: board.currentURLString)?.host(percentEncoded: false) ?? board.currentURLString
    }
}

private struct SheetStackIndicator: View {
    let canGoBack: Bool
    let canGoForward: Bool

    var body: some View {
        HStack(spacing: 3) {
            Capsule()
                .fill(canGoBack ? .black.opacity(0.28) : .black.opacity(0.12))
                .frame(width: 16, height: 6)

            Capsule()
                .fill(.black.opacity(0.84))
                .frame(width: 18, height: 6)

            Capsule()
                .fill(canGoForward ? .black.opacity(0.28) : .black.opacity(0.12))
                .frame(width: 16, height: 6)
        }
        .accessibilityLabel("Sheet stack")
    }
}
