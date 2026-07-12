import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ContentUnavailableView(
                "No Features Available",
                systemImage: "puzzlepiece.extension",
                description: Text("Optional browsing features will appear here.")
            )
            .tabItem {
                Label("Features", systemImage: "puzzlepiece.extension")
            }
        }
        .frame(width: 520, height: 360)
    }
}
