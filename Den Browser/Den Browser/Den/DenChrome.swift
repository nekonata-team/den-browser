import SwiftUI

struct DenBackground: View {
    let isDenMode: Bool
    let profileColor: Color

    var body: some View {
        LinearGradient(
            colors: isDenMode
                ? [
                    Color(red: 0.03, green: 0.18, blue: 0.23),
                    Color(red: 0.06, green: 0.10, blue: 0.18),
                ]
                : [
                    Color(red: 0.08, green: 0.10, blue: 0.12),
                    Color(red: 0.15, green: 0.16, blue: 0.19),
                ],
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

struct EmptyDenView: View {
    let openBoard: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Den Browser")
                    .font(.system(size: 28, weight: .semibold))

                Text("Open a board to start arranging web work.")
                    .font(.system(size: 14))
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
