import AppKit
import DenDomain
import DenModels
import DenViews
import Foundation
import Observation
import SwiftUI
import Synchronization
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct BoardFacingCacheTests {
    private func image(pixels: Int = 100, logicalSize: CGFloat = 100) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: logicalSize, height: logicalSize))
    }

    @Test func facingReadsPublishCapture() {
        // Arrange
        let cache = BoardFacingCache()
        let boardID = BoardID()
        let changed = Mutex(false)
        withObservationTracking {
            _ = cache.image(for: boardID)
        } onChange: {
            changed.withLock { $0 = true }
        }

        // Act
        cache.setFacing(image(), for: boardID)

        // Assert
        #expect(cache.image(for: boardID) != nil)
        #expect(changed.withLock { $0 })
    }

    @Test func facingReadsPublishInvalidation() {
        // Arrange
        let cache = BoardFacingCache()
        let boardID = BoardID()
        cache.setFacing(image(), for: boardID)
        let removed = Mutex(false)
        withObservationTracking {
            _ = cache.image(for: boardID)
        } onChange: {
            removed.withLock { $0 = true }
        }

        // Act
        cache.invalidate(for: boardID)

        // Assert
        #expect(cache.image(for: boardID) == nil)
        #expect(removed.withLock { $0 })
    }

    @Test func rasterPixelsDetermineBudgetRegardlessOfLogicalSize() {
        // Arrange
        let facing = image(pixels: 200, logicalSize: 100)
        let raster = facing.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let cache = BoardFacingCache(maxCost: raster.bytesPerRow * raster.height / 2)
        let boardID = BoardID()

        // Act
        cache.setFacing(facing, for: boardID)

        // Assert
        #expect(cache.image(for: boardID) == nil)
    }

    @Test func budgetEvictsLeastRecentlyReadImage() {
        // Arrange
        let facing = image()
        let raster = facing.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let cache = BoardFacingCache(maxCost: 2 * raster.bytesPerRow * raster.height)
        let first = BoardID()
        let second = BoardID()
        let third = BoardID()
        cache.setFacing(facing, for: first)
        cache.setFacing(facing, for: second)
        _ = cache.image(for: first)

        // Act
        cache.setFacing(facing, for: third)

        // Assert
        #expect(cache.image(for: first) != nil)
        #expect(cache.image(for: second) == nil)
        #expect(cache.image(for: third) != nil)
    }

    @Test func suppressionExpiresWithoutDiscardingImage() {
        // Arrange
        let cache = BoardFacingCache()
        let capture = BoardFacingCapture(cache: cache)
        let fresh = BoardID()
        let old = BoardID()
        cache.setFacing(image(), for: fresh)
        cache.setFacing(
            image(),
            for: old,
            at: .now - BoardFacingCapture.recaptureSuppressionDuration - .seconds(1)
        )

        // Act
        let freshAllowed = capture.shouldCapture(boardID: fresh)
        let oldAllowed = capture.shouldCapture(boardID: old)

        // Assert
        #expect(!freshAllowed)
        #expect(oldAllowed)
        #expect(cache.image(for: old) != nil)
    }

    @Test(arguments: [false, true]) func invalidationRejectsOutstandingCapture(clearProfile: Bool) {
        // Arrange
        let cache = BoardFacingCache()
        let capture = BoardFacingCapture(cache: cache)
        let boardID = BoardID()
        let old = cache.beginCapture(for: boardID)
        #expect(!capture.shouldCapture(boardID: boardID))

        // Act
        if clearProfile { cache.removeAll() } else { cache.invalidate(for: boardID) }
        _ = cache.beginCapture(for: boardID)
        cache.setCapturedFacing(image(), for: boardID, token: old)
        cache.finishCapture(old, for: boardID)

        // Assert
        #expect(cache.image(for: boardID) == nil)
        #expect(cache.isCapturing(boardID))
    }

    @Test func cancelledWebCaptureDoesNotPublishItsImage() async throws {
        // Arrange
        let cache = BoardFacingCache()
        let capture = BoardFacingCapture(cache: cache)
        let boardID = BoardID()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = DeferredFacingWebView(
            frame: NSRect(x: 0, y: 0, width: 100, height: 100),
            configuration: configuration
        )
        let task = Task { await capture.captureWeb(boardID: boardID, webView: web) }
        let deadline = ContinuousClock.now + .seconds(3)
        while web.pending == nil && ContinuousClock.now < deadline { await Task.yield() }
        let complete = try #require(web.pending)

        // Act
        task.cancel()
        complete(image(), nil)
        await task.value

        // Assert
        #expect(cache.image(for: boardID) == nil)
        #expect(!cache.isCapturing(boardID))
    }

    @Test func bottomDrawerHidesBoardSurfacesWithoutCapturingFacings() async throws {
        // Arrange
        let terminalBoard = BoardState(width: 520, workingDirectory: "/tmp")
        let webBoard = BoardState(label: "Web", width: 520, currentSheetURL: nil)
        let session = try makeKeyboardTestSession(boards: [terminalBoard, webBoard])
        session.configuration.preferences.setDrawerStyle(.bottom)
        let composition = DenWindowComposition(session: session)
        let terminalSurface = NSView()
        let webSurface = NSView()
        var terminalCaptures = 0
        var webCaptures = 0
        let root = HStack {
            DenViews.TerminalBoardView(
                model: BoardSurfaceModel(board: terminalBoard, session: session),
                board: terminalBoard,
                isFocused: true,
                focusRequest: nil,
                isDragging: false,
                profileColor: .blue,
                width: 520,
                height: 400,
                isPointerFocusEnabled: true,
                isVisibleInViewport: true,
                onFocus: {},
                onRemove: {},
                onDragChanged: { _ in },
                onDragEnded: { _ in },
                surface: terminalSurface,
                onSurfaceReady: { _ in true },
                onBeforeHide: { terminalCaptures += 1 },
                onSurfaceVisibilityChange: { _ in },
                onAdjustFontSize: { $0 }
            )
            DenViews.WebBoardView(
                model: BoardSurfaceModel(board: webBoard, session: session),
                board: webBoard,
                isFocused: false,
                focusRequest: nil,
                isDragging: false,
                profileColor: .blue,
                width: 520,
                height: 400,
                isPointerFocusEnabled: true,
                isVisibleInViewport: true,
                onFocus: {},
                onGoToFirst: {},
                onGoBack: {},
                onGoForward: {},
                onRemove: {},
                onDragChanged: { _ in },
                onDragEnded: { _ in },
                surface: webSurface,
                onSurfaceReady: { _ in true },
                onBeforeHide: { webCaptures += 1 },
                faviconURL: nil,
                isShowingInitialLoadFallback: false,
                isLoading: false,
                estimatedProgress: 0,
                canGoBack: false,
                canGoForward: false,
                highlightID: nil,
                highlightRect: nil,
                onAppear: {},
                onActivate: {},
                onReload: {},
                onHardReload: {},
                onPictureInPicture: {}
            )
        }
        .environment(composition.model)
        .environment(composition.model.deskFilter)
        let window = TestWindow()
        defer { window.contentView = nil }
        window.contentView = NSHostingView(rootView: root)
        window.contentView?.layoutSubtreeIfNeeded()

        // Act / Assert: Bottom Drawer hides surfaces without capturing facings
        composition.model.openDrawer()
        window.contentView?.layoutSubtreeIfNeeded()
        for _ in 0..<5 where !webSurface.isHidden { await Task.yield() }
        #expect(terminalSurface.isHidden)
        #expect(webSurface.isHidden)
        #expect(terminalCaptures == 0)
        #expect(webCaptures == 0)

        // Act / Assert: Closing Drawer restores visibility; Overview hides and captures facings
        composition.model.closeDrawer()
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(!terminalSurface.isHidden)
        #expect(!webSurface.isHidden)

        composition.model.showOverview()
        window.contentView?.layoutSubtreeIfNeeded()
        for _ in 0..<5 where !webSurface.isHidden { await Task.yield() }
        #expect(terminalSurface.isHidden)
        #expect(webSurface.isHidden)
        #expect(terminalCaptures == 1)
        #expect(webCaptures == 1)
    }
}

@MainActor
private final class DeferredFacingWebView: WKWebView {
    var pending: (@MainActor @Sendable (NSImage?, (any Error)?) -> Void)?
    override var url: URL? { URL(string: "https://facing.example/") }

    override func takeSnapshot(
        with configuration: WKSnapshotConfiguration?,
        completionHandler: (@MainActor @Sendable (NSImage?, (any Error)?) -> Void)?
    ) {
        pending = completionHandler
    }
}
