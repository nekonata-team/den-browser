import Foundation

// 2026-10-13: Swift 6 compiler bug workaround (SIL PerformanceSILLinker crash during cross-module WMO)
enum OverviewCanvasGeometry {
    public static func initialScale(boardSize: CGSize, neighborhoodHeight: CGFloat, viewportSize: CGSize) -> CGFloat {
        guard boardSize.width > 0, neighborhoodHeight > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return 1
        }
        return min(viewportSize.width * 0.65 / boardSize.width, viewportSize.height * 0.9 / neighborhoodHeight)
    }

    public static func centeringInset(contentSize: CGSize, viewportSize: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, (viewportSize.width - contentSize.width) / 2),
            y: max(0, (viewportSize.height - contentSize.height) / 2))
    }

    public static func zoomOffset(
        offset: CGPoint, anchor: CGPoint, contentSize: CGSize, viewportSize: CGSize, factor: CGFloat
    )
        -> CGPoint
    {
        let before = centeringInset(
            contentSize: contentSize,
            viewportSize: viewportSize)
        let after = centeringInset(
            contentSize: CGSize(width: contentSize.width * factor, height: contentSize.height * factor),
            viewportSize: viewportSize)
        return CGPoint(
            x: (offset.x + anchor.x - before.x) * factor + after.x - anchor.x,
            y: (offset.y + anchor.y - before.y) * factor + after.y - anchor.y)
    }

    public static func clampedOffset(_ offset: CGPoint, contentSize: CGSize, viewportSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, offset.x), max(0, contentSize.width - viewportSize.width)),
            y: min(max(0, offset.y), max(0, contentSize.height - viewportSize.height)))
    }
}
