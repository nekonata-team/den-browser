import CoreLocation
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct GeolocationPermissionTests {
    @Test(.timeLimit(.minutes(1)))
    func websiteGeolocationRequestsRequireUserConfirmation() async throws {
        // Arrange
        let runtime = GeolocationPermissionRuntime(
            id: UUID(),
            initialURL: nil,
            websiteDataStore: .nonPersistent(),
            userContentController: nil,
            sheetScale: 100,
            makeWebView: { RuntimeWKWebView(frame: .zero, configuration: $0) }
        )
        defer { runtime.dispose() }
        let webView = try #require(runtime.webView as? RuntimeWKWebView)
        webView.setBackgroundExecutionEnabled(true)
        defer { webView.setBackgroundExecutionEnabled(false) }

        // Act
        let decision = await withCheckedContinuation { continuation in
            runtime.permissionCompletion = continuation
            webView.loadHTMLString(
                "<script>navigator.geolocation.getCurrentPosition(() => {}, () => {});</script>",
                baseURL: URL(string: "https://example.com/")!
            )
        }

        // Assert
        #expect(decision == .prompt)
        #expect(
            runtime.responds(
                to: NSSelectorFromString(
                    "_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:"
                )
            )
        )
        if #available(macOS 27.0, *) {
            #expect(!runtime.usedPrivateDelegate)
        } else {
            #expect(runtime.usedPrivateDelegate)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: LocationScenario.allCases)
    func locationProviderDeliversPositionsAndRecovers(scenario: LocationScenario) async throws {
        // Arrange
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = RuntimeWKWebView(frame: .zero, configuration: configuration)
        let source = TestLocationManager()
        source.denied = scenario == .denied
        let watches = scenario == .networkRecovery || scenario == .permissionRecovery
        source.sendsPositionsAutomatically = !watches
        let provider = WebGeolocationProvider.install(for: webView, locationManager: source)
        let runtime = GeolocationPermissionRuntime(
            id: UUID(),
            initialURL: nil,
            websiteDataStore: .nonPersistent(),
            userContentController: nil,
            sheetScale: 100,
            existingWebView: webView
        )
        defer { runtime.dispose() }
        runtime.permissionDecision = .grant
        let messages = LocationResultHandler()
        configuration.userContentController.add(messages, name: "locationResult")
        defer { configuration.userContentController.removeScriptMessageHandler(forName: "locationResult") }
        webView.setBackgroundExecutionEnabled(true)
        defer { webView.setBackgroundExecutionEnabled(false) }

        // Act
        var results = messages.results.makeAsyncIterator()
        var stopsBeforePosition = 0
        webView.loadHTMLString(
            """
            <script>
            const watchID = navigator.geolocation.\(watches ? "watchPosition" : "getCurrentPosition")(
              p => {
                if (\(watches)) navigator.geolocation.clearWatch(watchID);
                webkit.messageHandlers.locationResult.postMessage(
                  p.coords.latitude === 1 && p.coords.longitude === 2 ? 'position' : 'invalid');
              },
              e => webkit.messageHandlers.locationResult.postMessage('error:' + e.code),
              { enableHighAccuracy: true });
            </script>
            """,
            baseURL: URL(string: "https://example.com/")!
        )
        if watches {
            await source.waitForStart()
            if scenario == .networkRecovery {
                provider.locationManager(source, didFailWithError: CLError(.network))
            } else {
                source.denied = true
                provider.locationManagerDidChangeAuthorization(source)
            }
            #expect(await results.next() == "error:2")
            if scenario == .permissionRecovery {
                source.sendPosition(latitude: 3)
                source.denied = false
                provider.locationManagerDidChangeAuthorization(source)
                try #require(source.startCount == 2)
            } else {
                try #require(source.stopCount == 0)
            }
            stopsBeforePosition = source.stopCount
            source.sendPosition()
        }
        let result = await results.next()
        await source.waitForStop(after: stopsBeforePosition)

        // Assert
        #expect(result == (scenario == .denied ? "error:2" : "position"))
        #expect(source.startCount == (scenario == .denied ? 0 : scenario == .permissionRecovery ? 2 : 1))
        #expect(source.desiredAccuracy == kCLLocationAccuracyBest)
        #expect(provider === WebGeolocationProvider.install(for: webView))
        if watches {
            let startsAfterStop = source.startCount
            provider.locationManagerDidChangeAuthorization(source)
            #expect(source.startCount == startsAfterStop)
        }
    }
}

enum LocationScenario: CaseIterable, Sendable {
    case position, denied, networkRecovery, permissionRecovery
}

@MainActor
private final class GeolocationPermissionRuntime: BaseWebRuntime {
    var permissionCompletion: CheckedContinuation<WKPermissionDecision, Never>?
    var permissionDecision: WKPermissionDecision = .deny
    var usedPrivateDelegate = false

    @available(macOS 27.0, *)
    override func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        super.webView(webView, requestGeolocationPermissionFor: origin, initiatedByFrame: frame) { decision in
            self.permissionCompletion?.resume(returning: decision)
            self.permissionCompletion = nil
            // Exercise the permission request without opening a dialog or accessing location in tests.
            decisionHandler(self.permissionDecision)
        }
    }

    override func webView(
        _ webView: WKWebView,
        requestPrivateGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        usedPrivateDelegate = true
        super.webView(webView, requestPrivateGeolocationPermissionFor: origin, initiatedByFrame: frame) { decision in
            self.permissionCompletion?.resume(returning: decision)
            self.permissionCompletion = nil
            decisionHandler(self.permissionDecision)
        }
    }
}

@MainActor
private final class LocationResultHandler: NSObject, WKScriptMessageHandler {
    let (results, continuation) = AsyncStream.makeStream(of: String.self)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        continuation.yield(message.body as? String ?? "invalid")
    }
}

@MainActor
private final class TestLocationManager: CLLocationManager, @unchecked Sendable {
    var denied = false
    var sendsPositionsAutomatically = true
    var startCount = 0
    private(set) var stopCount = 0
    private var startCompletion: CheckedContinuation<Void, Never>?
    private var stopCompletion: CheckedContinuation<Void, Never>?
    override var authorizationStatus: CLAuthorizationStatus {
        MainActor.assumeIsolated { denied ? .denied : .authorizedAlways }
    }

    override func startUpdatingLocation() {
        MainActor.assumeIsolated {
            startCount += 1
            startCompletion?.resume()
            startCompletion = nil
            if sendsPositionsAutomatically { sendPosition() }
        }
    }

    func sendPosition(latitude: Double = 1) {
        let location = CLLocation(
            coordinate: .init(latitude: latitude, longitude: 2),
            altitude: 0,
            horizontalAccuracy: 1,
            verticalAccuracy: 1,
            timestamp: Date()
        )
        delegate?.locationManager?(self, didUpdateLocations: [location])
    }

    override func stopUpdatingLocation() {
        MainActor.assumeIsolated {
            stopCount += 1
            stopCompletion?.resume()
            stopCompletion = nil
        }
    }

    func waitForStop(after count: Int = 0) async {
        if stopCount > count { return }
        await withCheckedContinuation { stopCompletion = $0 }
    }

    func waitForStart() async {
        if startCount > 0 { return }
        await withCheckedContinuation { startCompletion = $0 }
    }
}
