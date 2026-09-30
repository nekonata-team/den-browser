import SFSafeSymbols
import SwiftUI

struct DenBackground: View {
    let isDenMode: Bool
    let isPrivateDen: Bool
    let profileColor: Color

    var body: some View {
        let backgroundColors =
            if isPrivateDen {
                isDenMode
                    ? DenSurfaceColors.privateDenModeBackgroundGradientColors
                    : DenSurfaceColors.privateDenBackgroundGradientColors
            } else {
                isDenMode
                    ? DenSurfaceColors.denModeBackgroundGradientColors
                    : DenSurfaceColors.standardBackgroundGradientColors
            }
        let accentColor = profileColor

        LinearGradient(
            colors: backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(accentColor.opacity(isDenMode ? 0.22 : 0.12))
                .blur(radius: 120)
                .frame(width: 420, height: 280)
                .offset(x: -120, y: -80)
        }
        .overlay(alignment: .topTrailing) {
            Rectangle()
                .fill(accentColor.opacity(isDenMode ? 0.05 : 0.10))
                .blur(radius: 140)
                .frame(width: 420, height: 280)
                .offset(x: 140, y: -90)
        }
        .ignoresSafeArea()
    }
}

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

struct EmptyDenView: View {
    let openBoard: () -> Void
    let openTutorial: () -> Void
    let showKeyboardShortcuts: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Den Browser")
                    .font(.title.weight(.semibold))

                Text("Open a board to start arranging web work.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Group {
                    Button("Open Board", action: openBoard)
                        .buttonStyle(.glassProminent)

                    Button("Try Tutorial", action: openTutorial)
                        .buttonStyle(.glass)
                }
                .controlSize(.large)

                Button("Keyboard Shortcuts", action: showKeyboardShortcuts)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}
