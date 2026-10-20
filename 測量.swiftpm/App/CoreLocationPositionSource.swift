import CoreLocation
import Foundation
import SurveyCore

/// 段階0。iPhone の GPS だけを出す。CLAS と RTK の受信機は、同じ PositionSource で後から足す。
final class CoreLocationPositionSource: NSObject, PositionSource, CLLocationManagerDelegate {
    let receiver: ReceiverKind = .iphoneGPS
    let stage: PositionStage = .iphone
    let readings: AsyncStream<PositionReading>
    private let continuation: AsyncStream<PositionReading>.Continuation
    private let manager = CLLocationManager()
    private var lastPosition: GeodeticPosition?
    private var didRequestAuthorization = false

    override init() {
        let pair = AsyncStream<PositionReading>.makeStream()
        self.readings = pair.stream
        self.continuation = pair.continuation
        super.init()
    }

    func start() {
        if manager.delegate == nil {
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = kCLDistanceFilterNone
            manager.pausesLocationUpdatesAutomatically = false
            manager.activityType = .other
            manager.delegate = self
        }
        handle(manager.authorizationStatus)
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handle(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let height: Double? = location.verticalAccuracy >= 0 ? location.ellipsoidalAltitude : nil
        let vertical: Double? = location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
        let position = IPhonePosition.make(
            latitudeDegrees: location.coordinate.latitude,
            longitudeDegrees: location.coordinate.longitude,
            ellipsoidalHeightMeters: height,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            verticalAccuracyMeters: vertical,
            timestamp: location.timestamp
        )
        lastPosition = position
        continuation.yield(PositionReading(position: position, availability: .available))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        if code == .locationUnknown {
            return
        }
        if code == .denied {
            continuation.yield(PositionReading(position: lastPosition, availability: .denied))
            return
        }
        continuation.yield(PositionReading(position: lastPosition, availability: .unavailable))
    }

    private func handle(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .notDetermined:
            continuation.yield(PositionReading(position: lastPosition, availability: .waiting))
            if !didRequestAuthorization {
                didRequestAuthorization = true
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            continuation.yield(PositionReading(position: lastPosition, availability: .denied))
        @unknown default:
            continuation.yield(PositionReading(position: lastPosition, availability: .waiting))
        }
    }
}
