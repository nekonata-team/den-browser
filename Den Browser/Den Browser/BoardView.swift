import SwiftUI
import WebKit

struct BoardView: View {
    let board: BoardState
    let isFocused: Bool
    let isHeld: Bool
    let runtime: BoardRuntime
    let height: Double
    let isPointerFocusEnabled: Bool
    let onFocus: () -> Void
    let onGoBack: () -> Void
    let onGoForward: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .onTapGesture {
                    guard isPointerFocusEnabled else { return }
                    onFocus()
                }
            BoardWebView(
                webView: runtime.webView,
                isFocused: isFocused,
                isPointerFocusEnabled: isPointerFocusEnabled,
                onFocus: onFocus
            )
        }
        .frame(width: board.width, height: height)
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
        return Color.primary.opacity(0.16)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(board.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityLabel("Board: \(board.label), \(accessibilityState)")

            Spacer(minLength: 8)

            navigationButtons
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.regularMaterial)
        .contentShape(Rectangle())
    }

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            Button(action: onGoBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(!runtime.webView.canGoBack)
            .help("Back in sheet stack")
            .accessibilityLabel("Back in sheet stack")

            Button(action: onGoForward) {
                Image(systemName: "chevron.right")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .disabled(!runtime.webView.canGoForward)
            .help("Forward in sheet stack")
            .accessibilityLabel("Forward in sheet stack")
        }
    }

    private var accessibilityState: String {
        if isHeld {
            return "Held board"
        }
        if isFocused {
            return "Focused board"
        }
        return "Board"
    }
}
