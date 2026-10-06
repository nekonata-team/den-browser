import SwiftUI

public enum MotionPreference: String, CaseIterable, Identifiable {
    case followSystem = "follow-system"
    case standard
    case reduced

    public var id: Self { self }

    public var label: String {
        switch self {
        case .followSystem: "Follow System"
        case .standard: "Standard Motion"
        case .reduced: "Reduced Motion"
        }
    }
}

public enum DenRadius {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 18
}

public enum DenMotion {
    public static func shouldReduceMotion(
        preference: MotionPreference,
        systemReduceMotion: Bool
    ) -> Bool {
        switch preference {
        case .followSystem: systemReduceMotion
        case .standard: false
        case .reduced: true
        }
    }

    public static func spatial(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0)
    }

    public static func feedback(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.10) : .smooth(duration: 0.16, extraBounce: 0)
    }

    public static func transition(reduceMotion: Bool, scale: Double) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: scale).combined(with: .opacity)
    }

    public static func transition(reduceMotion: Bool, edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
