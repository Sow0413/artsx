import MapKit
import SwiftUI
import SurveyCore

struct SurveyMapView: UIViewRepresentable {
    @ObservedObject var field: FieldModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.pointOfInterestFilter = .excludingAll
        map.isPitchEnabled = false
        map.showsTraffic = false
        map.backgroundColor = SurveyUIColor.mapBackdrop
        context.coordinator.attach(field: field, map: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.attach(field: field, map: map)
        context.coordinator.update(
            map: map,
            reading: field.reading,
            viewport: field.viewport,
            followUser: field.followUser,
            tone: field.badge.tone,
            offlineRevision: field.offlineRevision
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var onUserPan: () -> Void = {}
        private var onVisible: (GeoBounds, Int) -> Void = { _, _ in }
        private var store: TileStore?
        private var tileOverlay: MKTileOverlay?
        private var circle: MKCircle?
        private var annotation: UserDotAnnotation?
        private var tone: AccuracyTone = .grey
        private var appliedViewport: MapViewport?
        private var circleKey: String?
        private var offlineRevision = 0
        private var didSetInitialRegion = false
        private var applyingProgrammaticRegion = false
        private var wasFollowing = true

        func attach(field: FieldModel, map: MKMapView) {
            store = field.tiles
            onUserPan = { [weak field] in
                field?.userPannedMap()
            }
            onVisible = { [weak field] bounds, zoom in
                field?.noteVisible(bounds: bounds, zoom: zoom)
            }
            if tileOverlay == nil {
                installTiles(on: map)
            }
        }

        func update(
            map: MKMapView,
            reading: PositionReading,
            viewport: MapViewport,
            followUser: Bool,
            tone: AccuracyTone,
            offlineRevision: Int
        ) {
            self.tone = tone
            if offlineRevision != self.offlineRevision {
                self.offlineRevision = offlineRevision
                installTiles(on: map)
            }
            syncAnnotation(on: map, reading: reading)
            syncCircle(on: map, reading: reading, tone: tone)
            if followUser, !wasFollowing {
                appliedViewport = nil
            }
            wasFollowing = followUser
            guard followUser, appliedViewport != viewport else { return }
            appliedViewport = viewport
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: viewport.centerLatitude, longitude: viewport.centerLongitude),
                span: MKCoordinateSpan(latitudeDelta: viewport.latitudeDelta, longitudeDelta: viewport.longitudeDelta)
            )
            applyingProgrammaticRegion = true
            map.setRegion(region, animated: didSetInitialRegion)
            applyingProgrammaticRegion = false
            didSetInitialRegion = true
            reportVisible(map)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard !applyingProgrammaticRegion else { return }
            guard Self.isUserGesture(on: mapView) else { return }
            onUserPan()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            reportVisible(mapView)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                let color = tone.circle
                renderer.fillColor = color.withAlphaComponent(tone == .green ? 0.30 : 0.22)
                renderer.strokeColor = color
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is UserDotAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "user-dot")
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "user-dot")
            view.annotation = annotation
            view.image = Self.userDotImage
            view.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
            view.canShowCallout = false
            return view
        }

        private func installTiles(on map: MKMapView) {
            guard let store else { return }
            if let tileOverlay {
                map.removeOverlay(tileOverlay)
            }
            let overlay = GSITileOverlay(store: store)
            tileOverlay = overlay
            map.addOverlay(overlay, level: .aboveLabels)
            if let circle {
                map.removeOverlay(circle)
                map.addOverlay(circle, level: .aboveLabels)
            }
        }

        private func syncAnnotation(on map: MKMapView, reading: PositionReading) {
            guard let position = reading.position, position.isPlottable else {
                if let annotation {
                    map.removeAnnotation(annotation)
                    self.annotation = nil
                }
                return
            }
            let coordinate = CLLocationCoordinate2D(
                latitude: position.latitudeDegrees,
                longitude: position.longitudeDegrees
            )
            if let annotation {
                annotation.coordinate = coordinate
                return
            }
            let created = UserDotAnnotation(coordinate: coordinate)
            annotation = created
            map.addAnnotation(created)
        }

        private func syncCircle(on map: MKMapView, reading: PositionReading, tone: AccuracyTone) {
            guard let position = reading.position,
                  position.isPlottable,
                  position.hasValidHorizontalAccuracy else {
                if let circle {
                    map.removeOverlay(circle)
                    self.circle = nil
                    circleKey = nil
                }
                return
            }
            let key = "\(position.latitudeDegrees) \(position.longitudeDegrees) \(position.horizontalAccuracyMeters) \(tone.rawValue)"
            if key == circleKey { return }
            if let circle {
                map.removeOverlay(circle)
            }
            let overlay = MKCircle(
                center: CLLocationCoordinate2D(latitude: position.latitudeDegrees, longitude: position.longitudeDegrees),
                radius: position.horizontalAccuracyMeters
            )
            circle = overlay
            circleKey = key
            map.addOverlay(overlay, level: .aboveLabels)
        }

        private func reportVisible(_ map: MKMapView) {
            guard map.bounds.width > 1 else { return }
            let region = map.region
            let bounds = GeoBounds(
                south: region.center.latitude - region.span.latitudeDelta / 2,
                west: region.center.longitude - region.span.longitudeDelta / 2,
                north: region.center.latitude + region.span.latitudeDelta / 2,
                east: region.center.longitude + region.span.longitudeDelta / 2
            )
            let zoom = MapZoom.level(
                longitudeDelta: region.span.longitudeDelta,
                screenWidthPoints: Double(map.bounds.width)
            )
            onVisible(bounds, zoom)
        }

        private static func isUserGesture(on mapView: MKMapView) -> Bool {
            let recognizers = mapView.subviews.flatMap { $0.gestureRecognizers ?? [] }
            return recognizers.contains { gesture in
                switch gesture.state {
                case .began, .changed, .ended, .cancelled:
                    return true
                default:
                    return false
                }
            }
        }

        private static let userDotImage: UIImage = {
            let size = CGSize(width: 28, height: 28)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                UIColor.white.setFill()
                context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
                SurveyUIColor.blue.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 4, y: 4, width: 20, height: 20))
            }
        }()
    }
}

final class UserDotAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}
