import CoreLocation
import Foundation
import WebKit

@MainActor
final class WebGeolocationProvider: NSObject, CLLocationManagerDelegate {
    private static let providers = NSMapTable<NSObject, WebGeolocationProvider>.weakToWeakObjects()

    static func install(
        for webView: WKWebView,
        locationManager: CLLocationManager = CLLocationManager()
    ) -> WebGeolocationProvider {
        let context = DenGeolocationContext(webView)
        if let provider = providers.object(forKey: context) { return provider }
        let provider = WebGeolocationProvider(context: context, locationManager: locationManager)
        providers.setObject(provider, forKey: context)
        return provider
    }

    private let context: NSObject
    private let manager: WKGeolocationManagerRef
    private let locationManager: CLLocationManager
    private var hasActiveRequests = false

    private init(context: NSObject, locationManager: CLLocationManager) {
        self.context = context
        manager = WKContextGetGeolocationManager(OpaquePointer(Unmanaged.passUnretained(context).toOpaque()))
        self.locationManager = locationManager
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        // WebKit invokes provider callbacks on the UI thread and copies this callback table.
        var provider = WKGeolocationProviderV1(
            base: .init(version: 1, clientInfo: Unmanaged.passUnretained(self).toOpaque()),
            startUpdating: { _, info in
                MainActor.assumeIsolated {
                    Unmanaged<WebGeolocationProvider>.fromOpaque(info).takeUnretainedValue().start()
                }
            },
            stopUpdating: { _, info in
                MainActor.assumeIsolated {
                    Unmanaged<WebGeolocationProvider>.fromOpaque(info).takeUnretainedValue().stop()
                }
            },
            setEnableHighAccuracy: { _, enabled, info in
                MainActor.assumeIsolated {
                    let provider = Unmanaged<WebGeolocationProvider>.fromOpaque(info).takeUnretainedValue()
                    provider.locationManager.desiredAccuracy =
                        enabled
                        ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
                }
            }
        )
        withUnsafePointer(to: &provider) {
            WKGeolocationManagerSetProvider(
                manager,
                UnsafeRawPointer($0).assumingMemoryBound(to: WKGeolocationProviderBase.self)
            )
        }
    }

    isolated deinit {
        locationManager.stopUpdatingLocation()
        locationManager.delegate = nil
        WKGeolocationManagerSetProvider(manager, nil)
    }

    private func start() {
        hasActiveRequests = true
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            updateAuthorization()
        }
    }

    private func stop() {
        hasActiveRequests = false
        locationManager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if hasActiveRequests { updateAuthorization() }
    }

    private func updateAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            locationManager.stopUpdatingLocation()
            WKGeolocationManagerProviderDidFailToDeterminePosition(manager)
        case .notDetermined:
            break
        @unknown default:
            locationManager.stopUpdatingLocation()
            WKGeolocationManagerProviderDidFailToDeterminePosition(manager)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard hasActiveRequests, locationManager.authorizationStatus == .authorizedAlways,
            let location = locations.last, location.horizontalAccuracy >= 0
        else { return }
        let position = WKGeolocationPositionCreate(
            location.timestamp.timeIntervalSince1970,
            location.coordinate.latitude,
            location.coordinate.longitude,
            location.horizontalAccuracy
        )
        WKGeolocationManagerProviderDidChangePosition(self.manager, position)
        WKRelease(UnsafeRawPointer(position))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard hasActiveRequests, (error as? CLError)?.code != .locationUnknown else { return }
        WKGeolocationManagerProviderDidFailToDeterminePosition(self.manager)
    }
}
