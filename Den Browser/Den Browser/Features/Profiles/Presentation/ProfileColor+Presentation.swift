import AppKit
import SwiftUI

extension ProfileRGB {
    var color: Color {
        Color(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: 1)
    }

    init?(color: Color) {
        guard let color = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: Self.component(color.redComponent),
            green: Self.component(color.greenComponent),
            blue: Self.component(color.blueComponent))
    }

    private static func component(_ value: CGFloat) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }
}

extension ProfileColor {
    var rgb: ProfileRGB {
        switch self {
        case .custom(let rgb): rgb
        default: ProfileRGB(color: color) ?? ProfileRGB(red: 0, green: 0, blue: 0)
        }
    }

    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .green: .green
        case .yellow: .yellow
        case .gray: .gray
        case .custom(let rgb): rgb.color
        }
    }

    var label: String {
        switch self {
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .green: "Green"
        case .yellow: "Yellow"
        case .gray: "Gray"
        case .custom: "Custom"
        }
    }

    init?(color: Color) {
        guard let rgb = ProfileRGB(color: color) else { return nil }
        self = .custom(rgb)
    }
}
