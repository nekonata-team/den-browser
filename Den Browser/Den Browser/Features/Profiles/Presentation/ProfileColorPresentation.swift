import AppKit
import SwiftUI

func profileDisplayColor(for rgb: ProfileRGB) -> Color {
    Color(
        .sRGB,
        red: Double(rgb.red) / 255,
        green: Double(rgb.green) / 255,
        blue: Double(rgb.blue) / 255,
        opacity: 1)
}

func profileRGB(from color: Color) -> ProfileRGB? {
    guard let color = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    return ProfileRGB(
        red: profileColorComponent(color.redComponent),
        green: profileColorComponent(color.greenComponent),
        blue: profileColorComponent(color.blueComponent))
}

private func profileColorComponent(_ value: CGFloat) -> UInt8 {
    UInt8((min(max(value, 0), 1) * 255).rounded())
}

func profileRGB(for color: ProfileColor) -> ProfileRGB {
    switch color {
    case .custom(let rgb): rgb
    default: profileRGB(from: profileDisplayColor(for: color)) ?? ProfileRGB(red: 0, green: 0, blue: 0)
    }
}

func profileDisplayColor(for color: ProfileColor) -> Color {
    switch color {
    case .blue: .blue
    case .purple: .purple
    case .pink: .pink
    case .green: .green
    case .yellow: .yellow
    case .gray: .gray
    case .custom(let rgb): profileDisplayColor(for: rgb)
    }
}

func profileColorLabel(for color: ProfileColor) -> String {
    switch color {
    case .blue: "Blue"
    case .purple: "Purple"
    case .pink: "Pink"
    case .green: "Green"
    case .yellow: "Yellow"
    case .gray: "Gray"
    case .custom: "Custom"
    }
}

func profileColor(from color: Color) -> ProfileColor? {
    guard let rgb = profileRGB(from: color) else { return nil }
    return .custom(rgb)
}
