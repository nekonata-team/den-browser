import SwiftUI

struct DenColorToken {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

enum DenSurfaceColors {
    static let denModeBackground = [
        DenColorToken(red: 0.03, green: 0.18, blue: 0.23),
        DenColorToken(red: 0.06, green: 0.10, blue: 0.18),
    ]

    static let standardBackground = [
        DenColorToken(red: 0.08, green: 0.10, blue: 0.12),
        DenColorToken(red: 0.15, green: 0.16, blue: 0.19),
    ]

    static let webViewFallbackBackground = standardBackground[0]
}
