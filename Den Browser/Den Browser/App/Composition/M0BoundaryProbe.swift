import AppKit
import DenViews

/// Construction-only M0 probes for the later product screen migration.
enum M0BoundaryProbe {
    static func nativeSurface(_ view: NSView) -> NativeSurfaceView {
        NativeSurfaceView(surface: view)
    }
}
