import SwiftUI

struct DenBackground: View {
    let isDenMode: Bool
    let profileColor: Color

    var body: some View {
        LinearGradient(
            colors: (isDenMode
                ? DenSurfaceColors.denModeBackground
                : DenSurfaceColors.standardBackground).map(\.color),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(profileColor.opacity(isDenMode ? 0.22 : 0.12))
                .blur(radius: 120)
                .frame(width: 420, height: 280)
                .offset(x: -120, y: -80)
        }
        .overlay(alignment: .topTrailing) {
            Rectangle()
                .fill(profileColor.opacity(isDenMode ? 0.05 : 0.10))
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
            Image(systemName: "xmark")
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

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Den Browser")
                    .font(.title.weight(.semibold))

                Text("Open a board to start arranging web work.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            KeyboardShortcutsView()
                .padding(18)
                .frame(width: 760, height: 460)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DenRadius.large, style: .continuous))

            Button("Open Board", action: openBoard)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}
