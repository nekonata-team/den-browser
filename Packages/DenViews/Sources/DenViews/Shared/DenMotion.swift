public import DenModels
import SwiftUI

public enum DenRadius {
    /// Small controls; use a continuous corner shape.
    public static let small: CGFloat = 8
    /// Inner cards and inputs; use a continuous corner shape.
    public static let medium: CGFloat = 12
    /// Boards, panels, and Overview; use a continuous corner shape.
    public static let large: CGFloat = 18
}

/// Shared app-owned motion.
///
/// Resolve the preference with the system setting before choosing an animation.
/// Direct pointer tracking and continuous drag auto-scroll may use interaction-specific motion.
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

    /// Movement, resizing, and focus changes; Reduced Motion removes spatial animation.
    public static func spatial(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0)
    }

    /// Non-spatial feedback that retains a brief animation under Reduced Motion.
    public static func feedback(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeOut(duration: 0.10) : .smooth(duration: 0.16, extraBounce: 0)
    }

    /// Temporary panel presentation; Reduced Motion keeps only the opacity transition.
    public static func panelTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .center).combined(with: .opacity)
    }

    /// Edge-based presentation; Reduced Motion keeps only the opacity transition.
    public static func transition(reduceMotion: Bool, edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
