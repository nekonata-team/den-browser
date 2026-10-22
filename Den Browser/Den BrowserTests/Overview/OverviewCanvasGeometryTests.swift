import DenPresentationModels
import DenViews
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct OverviewCanvasGeometryTests {
    @Test func initialScaleFitsFocusedBoardInLandscapeAndPortrait() {
        // Arrange
        let board = CGSize(width: 150, height: 120)
        let landscape = CGSize(width: 1000, height: 600)
        let portrait = CGSize(width: 400, height: 1000)
        let neighborhoodHeight: CGFloat = 3 * 146 + 2 * 18

        // Act
        let wideScale = OverviewCanvasGeometry.initialScale(
            boardSize: board, neighborhoodHeight: neighborhoodHeight, viewportSize: landscape)
        let tallScale = OverviewCanvasGeometry.initialScale(
            boardSize: board, neighborhoodHeight: neighborhoodHeight, viewportSize: portrait)

        // Assert
        #expect(wideScale > 1)
        #expect(tallScale > 1)
        #expect(wideScale != tallScale)
        #expect(board.width * tallScale < portrait.width)
        #expect(board.height * wideScale < landscape.height)
        #expect(neighborhoodHeight * wideScale < landscape.height)
        #expect(neighborhoodHeight * tallScale < portrait.height)
    }

    @Test func zoomKeepsContentUnderGestureAnchor() {
        // Arrange
        let offset = CGPoint(x: 300, y: 100)
        let anchor = CGPoint(x: 150, y: 80)
        let oldScale: CGFloat = 2
        let newScale: CGFloat = 3

        // Act
        let next = OverviewCanvasGeometry.zoomOffset(
            offset: offset, anchor: anchor,
            contentSize: CGSize(width: 1000 * oldScale, height: 600 * oldScale),
            viewportSize: CGSize(width: 500, height: 300),
            factor: newScale / oldScale)

        // Assert
        #expect((offset.x + anchor.x) / oldScale == (next.x + anchor.x) / newScale)
        #expect((offset.y + anchor.y) / oldScale == (next.y + anchor.y) / newScale)
    }

    @Test func centeredContentKeepsItsCenterWhenGrowingBeyondViewport() {
        // Arrange
        let content = CGSize(width: 1000, height: 600)
        let viewport = CGSize(width: 1200, height: 800)
        let anchor = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let inset = OverviewCanvasGeometry.centeringInset(contentSize: content, viewportSize: viewport)

        // Act
        let next = OverviewCanvasGeometry.zoomOffset(
            offset: CGPoint(x: 0, y: 0), anchor: anchor,
            contentSize: content, viewportSize: viewport, factor: 2)

        // Assert
        #expect(anchor.x - inset.x == (next.x + anchor.x) / 2)
        #expect(anchor.y - inset.y == (next.y + anchor.y) / 2)
    }

    @Test func centeredContentNeedsNoOffsetWhenShrinkingWithinViewport() {
        // Arrange
        let content = CGSize(width: 1000, height: 600)
        let viewport = CGSize(width: 1200, height: 800)
        let anchor = CGPoint(x: viewport.width / 2, y: viewport.height / 2)

        // Act
        let next = OverviewCanvasGeometry.zoomOffset(
            offset: CGPoint(x: 0, y: 0), anchor: anchor,
            contentSize: content, viewportSize: viewport, factor: 0.5)

        // Assert
        #expect(next == CGPoint(x: 0, y: 0))
    }

    @Test func panStopsAtContentBoundsAndAllowsScaledTrailingEdge() {
        // Arrange
        let viewport = CGSize(width: 500, height: 300)
        let scaledContent = CGSize(width: 2000, height: 600)

        // Act
        let leading = OverviewCanvasGeometry.clampedOffset(
            CGPoint(x: -100, y: -100), contentSize: scaledContent, viewportSize: viewport)
        let trailing = OverviewCanvasGeometry.clampedOffset(
            CGPoint(x: 3000, y: 1000), contentSize: scaledContent, viewportSize: viewport)

        // Assert
        #expect(leading == CGPoint(x: 0, y: 0))
        #expect(trailing == CGPoint(x: scaledContent.width - viewport.width, y: scaledContent.height - viewport.height))
    }
}
