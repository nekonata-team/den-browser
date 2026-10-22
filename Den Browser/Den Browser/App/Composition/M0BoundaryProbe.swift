import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import DenViews

/// Construction-only M0 probes for the later product screen migration.
enum M0BoundaryProbe {
    static func boardOrder(state: DenStateStore, movement: BoardMovement, deskID: DeskID) -> BoardOrderProbeView {
        BoardOrderProbeView(model: BoardOrderProbeModel(state: state, movement: movement, deskID: deskID))
    }

    static func nativeSurface(_ view: NSView) -> NativeSurfaceView {
        NativeSurfaceView(surface: view)
    }
}
