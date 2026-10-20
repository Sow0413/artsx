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
            reading: field.workingReading,
            viewport: field.viewport,
            followUser: field.followUser,
            tone: field.badge.tone,
            offlineRevision: field.offlineRevision
        )
        context.coordinator.syncControls(
            on: map,
            points: field.visibleControlPoints,
            selectedID: field.selectedControlPointID
        )
        context.coordinator.syncDrawing(
            on: map,
            paths: field.drawing.mapPaths,
            revision: field.drawing.mapRevision
        )
        context.coordinator.syncReach(on: map, field: field)
        context.coordinator.syncCrew(on: map, field: field)
        context.coordinator.syncHeat(on: map, field: field)
        context.coordinator.setMapPick(field.drawing.pick == .mapPoint) { latitude, longitude in
            field.completeDrawingMapPick(latitude: latitude, longitude: longitude)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var onUserPan: () -> Void = {}
        private var onVisible: (GeoBounds, Int) -> Void = { _, _ in }
        private var onSelectControlPoint: (String) -> Void = { _ in }
        private var controlAnnotations: [String: ControlPointAnnotation] = [:]
        private var selectedControlID: String?
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
        private var drawingLines: [MKPolyline] = []
        private var drawingRevision = -1
        private var reachOverlays: [MKOverlay] = []
        private var reachKey = ""
        private var crewOverlays: [MKOverlay] = []
        private var crewAnnotations: [CrewAnnotation] = []
        private var crewKey = ""
        private var heatOverlays: [MKOverlay] = []
        private var heatKey = ""
        private var mapPick = false
        private var onMapTap: (Double, Double) -> Void = { _, _ in }

        func attach(field: FieldModel, map: MKMapView) {
            store = field.tiles
            onUserPan = { [weak field] in
                field?.userPannedMap()
            }
            onVisible = { [weak field] bounds, zoom in
                field?.noteVisible(bounds: bounds, zoom: zoom)
            }
            onSelectControlPoint = { [weak field] id in
                field?.selectControlPoint(id)
            }
            if tileOverlay == nil {
                installTiles(on: map)
                let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
                tap.cancelsTouchesInView = false
                map.addGestureRecognizer(tap)
            }
        }

        func setMapPick(_ enabled: Bool, handler: @escaping (Double, Double) -> Void) {
            mapPick = enabled
            onMapTap = handler
        }

        func syncReach(on map: MKMapView, field: FieldModel) {
            let position = field.workingReading.position
            let radius = field.drawing.machineRadiusMeters
            let target = field.drawing.operatorTarget(control: field.selectedControlPoint)
            let graphics: (center: PlanarPoint, radius: Double, ranges: [ReachRange], rings: [ReachRing])?
            if let position, position.isPlottable {
                graphics = field.drawing.reachGraphics(latitude: position.latitudeDegrees, longitude: position.longitudeDegrees)
            } else {
                graphics = nil
            }
            var call: ReachCall?
            if let position, position.isPlottable, let target {
                call = MachineReach.geodesic(
                    fromLatitude: position.latitudeDegrees,
                    fromLongitude: position.longitudeDegrees,
                    toLatitude: target.latitude,
                    toLongitude: target.longitude,
                    radiusMeters: radius
                )
            }
            let ringToken = graphics?.rings.map { "\($0.coverage.rawValue):\($0.coordinates.count)" }.joined(separator: ",") ?? ""
            let key = [
                position.map { String(format: "%.5f,%.5f", $0.latitudeDegrees, $0.longitudeDegrees) } ?? "-",
                String(format: "%.1f", radius),
                target.map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) } ?? "-",
                call?.coverage.rawValue ?? "-",
                ringToken,
                "\(field.drawing.mapRevision)"
            ].joined(separator: "|")
            if key == reachKey { return }
            reachKey = key
            if !reachOverlays.isEmpty {
                map.removeOverlays(reachOverlays)
                reachOverlays = []
            }
            guard let position, position.isPlottable, radius > 0 else { return }
            var judged: [ReachCoverage] = graphics?.rings.map(\.coverage) ?? []
            if let call { judged.append(call.coverage) }
            let diskColor = Self.reachColor(MachineReach.worst(judged))
            let disk = ReachCircleOverlay(
                center: CLLocationCoordinate2D(latitude: position.latitudeDegrees, longitude: position.longitudeDegrees),
                radius: radius
            )
            disk.stroke = diskColor
            disk.fill = diskColor.withAlphaComponent(0.08)
            disk.lineWidth = 3
            reachOverlays.append(disk)
            if let target, let call {
                let mark = ReachCircleOverlay(
                    center: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
                    radius: 3
                )
                let color = Self.reachColor(call.coverage)
                mark.stroke = color
                mark.fill = color.withAlphaComponent(0.55)
                mark.lineWidth = 2
                reachOverlays.append(mark)
            }
            for ring in graphics?.rings ?? [] {
                var coordinates = ring.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitudeDegrees, longitude: $0.longitudeDegrees)
                }
                let color = Self.reachColor(ring.coverage)
                if ring.closed, coordinates.count >= 3 {
                    let area = ReachAreaOverlay(coordinates: &coordinates, count: coordinates.count)
                    area.stroke = color
                    area.fill = color.withAlphaComponent(0.22)
                    reachOverlays.append(area)
                } else if coordinates.count >= 2 {
                    let line = ReachLineOverlay(coordinates: &coordinates, count: coordinates.count)
                    line.stroke = color
                    reachOverlays.append(line)
                }
            }
            map.addOverlays(reachOverlays, level: .aboveLabels)
        }

        func syncCrew(on map: MKMapView, field: FieldModel) {
            let key = field.crew.peers.map { peer in
                let level = field.crew.marks.first { $0.id == peer.id }?.level.rawValue ?? "clear"
                return "\(peer.id):\(peer.latitudeDegrees):\(peer.longitudeDegrees):\(peer.workRadiusMeters ?? 0):\(peer.role.rawValue):\(level)"
            }.joined(separator: "|")
            if key == crewKey { return }
            crewKey = key
            if !crewOverlays.isEmpty {
                map.removeOverlays(crewOverlays)
                crewOverlays = []
            }
            if !crewAnnotations.isEmpty {
                map.removeAnnotations(crewAnnotations)
                crewAnnotations = []
            }
            for peer in field.crew.peers {
                let level = field.crew.marks.first { $0.id == peer.id }?.level ?? .clear
                let coordinate = CLLocationCoordinate2D(latitude: peer.latitudeDegrees, longitude: peer.longitudeDegrees)
                let mark = CrewAnnotation(peerID: peer.id, role: peer.role, level: level, coordinate: coordinate, name: peer.name)
                crewAnnotations.append(mark)
                if peer.role == .machine, let radius = peer.workRadiusMeters, radius > 0 {
                    let disk = ReachCircleOverlay(center: coordinate, radius: radius)
                    let color = level == .alarm ? SurveyUIColor.red : (level == .caution ? SurveyUIColor.yellow : SurveyUIColor.amber)
                    disk.stroke = color
                    disk.fill = color.withAlphaComponent(0.1)
                    disk.lineWidth = 3
                    crewOverlays.append(disk)
                }
            }
            if !crewAnnotations.isEmpty {
                map.addAnnotations(crewAnnotations)
            }
            if !crewOverlays.isEmpty {
                map.addOverlays(crewOverlays, level: .aboveLabels)
            }
        }

        private static func reachColor(_ coverage: ReachCoverage?) -> UIColor {
            switch coverage {
            case .inside, .onRadius: return SurveyUIColor.green
            case .partial: return SurveyUIColor.yellow
            case .outside: return SurveyUIColor.red
            case nil: return SurveyUIColor.amber
            }
        }

        func syncDrawing(on map: MKMapView, paths: [GeographicPath], revision: Int) {
            guard revision != drawingRevision else { return }
            drawingRevision = revision
            if !drawingLines.isEmpty {
                map.removeOverlays(drawingLines)
            }
            drawingLines = paths.compactMap { path in
                var coordinates = path.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitudeDegrees, longitude: $0.longitudeDegrees)
                }
                guard coordinates.count >= 2 else { return nil }
                return MKPolyline(coordinates: &coordinates, count: coordinates.count)
            }
            if !drawingLines.isEmpty {
                map.addOverlays(drawingLines, level: .aboveLabels)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard mapPick, let map = gesture.view as? MKMapView else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            onMapTap(coordinate.latitude, coordinate.longitude)
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
            if let heat = overlay as? IncidentHeatOverlay {
                let renderer = MKCircleRenderer(circle: heat)
                renderer.fillColor = heat.fill
                renderer.strokeColor = heat.fill
                renderer.lineWidth = 0
                return renderer
            }
            if let disk = overlay as? ReachCircleOverlay {
                let renderer = MKCircleRenderer(circle: disk)
                renderer.fillColor = disk.fill
                renderer.strokeColor = disk.stroke
                renderer.lineWidth = disk.lineWidth
                return renderer
            }
            if let area = overlay as? ReachAreaOverlay {
                let renderer = MKPolygonRenderer(polygon: area)
                renderer.fillColor = area.fill
                renderer.strokeColor = area.stroke
                renderer.lineWidth = 2
                return renderer
            }
            if let reachLine = overlay as? ReachLineOverlay {
                let renderer = MKPolylineRenderer(polyline: reachLine)
                renderer.strokeColor = reachLine.stroke
                renderer.lineWidth = 3
                return renderer
            }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = SurveyUIColor.amber
                renderer.lineWidth = 1.5
                return renderer
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

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let point = view.annotation as? ControlPointAnnotation else { return }
            onSelectControlPoint(point.pointID)
            mapView.deselectAnnotation(point, animated: false)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let point = annotation as? ControlPointAnnotation {
                let marker = mapView.dequeueReusableAnnotationView(withIdentifier: ControlMarkerView.reuseID) as? ControlMarkerView
                    ?? ControlMarkerView(annotation: point, reuseIdentifier: ControlMarkerView.reuseID)
                marker.annotation = point
                marker.configure(title: point.title ?? point.pointID, selected: point.pointID == selectedControlID)
                return marker
            }
            if let crew = annotation as? CrewAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "crew-dot")
                    ?? MKAnnotationView(annotation: crew, reuseIdentifier: "crew-dot")
                view.annotation = crew
                view.image = crew.role == .machine ? Self.machineDot : Self.workerDot
                view.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
                view.canShowCallout = true
                return view
            }
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
            if !drawingLines.isEmpty {
                map.removeOverlays(drawingLines)
                map.addOverlays(drawingLines, level: .aboveLabels)
            }
            if !reachOverlays.isEmpty {
                map.removeOverlays(reachOverlays)
                map.addOverlays(reachOverlays, level: .aboveLabels)
            }
            if !crewOverlays.isEmpty {
                map.removeOverlays(crewOverlays)
                map.addOverlays(crewOverlays, level: .aboveLabels)
            }
            if !heatOverlays.isEmpty {
                map.removeOverlays(heatOverlays)
                map.addOverlays(heatOverlays, level: .aboveLabels)
            }
        }

        func syncHeat(on map: MKMapView, field: FieldModel) {
            guard field.showIncidentHeat else {
                if !heatOverlays.isEmpty {
                    map.removeOverlays(heatOverlays)
                    heatOverlays = []
                    heatKey = ""
                }
                return
            }
            let key = field.incidentHeat.map { "\($0.latitudeDegrees),\($0.longitudeDegrees),\($0.count)" }.joined(separator: "|")
            if key == heatKey { return }
            if !heatOverlays.isEmpty {
                map.removeOverlays(heatOverlays)
            }
            let maxCount = field.incidentHeat.map(\.count).max() ?? 1
            heatOverlays = field.incidentHeat.map { cell in
                let overlay = IncidentHeatOverlay(
                    center: CLLocationCoordinate2D(latitude: cell.latitudeDegrees, longitude: cell.longitudeDegrees),
                    radius: cell.radiusMeters
                )
                let heat = Double(cell.count) / Double(maxCount)
                overlay.fill = UIColor(red: 0.94, green: 0.35 + 0.4 * (1 - heat), blue: 0.15, alpha: 0.28 + 0.4 * heat)
                return overlay
            }
            heatKey = key
            map.addOverlays(heatOverlays, level: .aboveLabels)
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

        func syncControls(on map: MKMapView, points: [ControlPoint], selectedID: String?) {
            let ids = Set(points.map(\.id))
            for (id, annotation) in controlAnnotations where !ids.contains(id) {
                map.removeAnnotation(annotation)
                controlAnnotations.removeValue(forKey: id)
            }
            for point in points {
                let title = point.name
                if let existing = controlAnnotations[point.id] {
                    existing.coordinate = CLLocationCoordinate2D(
                        latitude: point.latitudeDegrees,
                        longitude: point.longitudeDegrees
                    )
                    existing.title = title
                } else {
                    let created = ControlPointAnnotation(
                        pointID: point.id,
                        coordinate: CLLocationCoordinate2D(latitude: point.latitudeDegrees, longitude: point.longitudeDegrees),
                        title: title
                    )
                    controlAnnotations[point.id] = created
                    map.addAnnotation(created)
                }
            }
            selectedControlID = selectedID
            for (id, annotation) in controlAnnotations {
                guard let marker = map.view(for: annotation) as? ControlMarkerView else { continue }
                marker.configure(title: annotation.title ?? id, selected: id == selectedID)
            }
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

        private static let workerDot = dot(SurveyUIColor.blue)
        private static let machineDot = dot(SurveyUIColor.amber)

        private static func dot(_ color: UIColor) -> UIImage {
            let size = CGSize(width: 28, height: 28)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                UIColor.white.setFill()
                context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
                color.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 4, y: 4, width: 20, height: 20))
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

final class ControlPointAnnotation: NSObject, MKAnnotation {
    let pointID: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?

    init(pointID: String, coordinate: CLLocationCoordinate2D, title: String) {
        self.pointID = pointID
        self.coordinate = coordinate
        self.title = title
        super.init()
    }
}

final class ControlMarkerView: MKAnnotationView {
    static let reuseID = "control-point"
    private let nameLabel = UILabel()
    private let triangle = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        nameLabel.font = .systemFont(ofSize: 13, weight: .bold)
        nameLabel.textColor = .black
        nameLabel.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        nameLabel.layer.cornerRadius = 4
        nameLabel.clipsToBounds = true
        addSubview(triangle)
        addSubview(nameLabel)
        canShowCallout = false
        isEnabled = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, selected: Bool) {
        nameLabel.text = " \(title) "
        nameLabel.sizeToFit()
        let triangleSide: CGFloat = 22
        let height: CGFloat = 44
        let width = max(44, triangleSide + 6 + nameLabel.bounds.width)
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        triangle.frame = CGRect(x: 0, y: (height - triangleSide) / 2, width: triangleSide, height: triangleSide)
        triangle.image = Self.triangle(selected: selected)
        nameLabel.frame = CGRect(
            x: triangleSide + 4,
            y: (height - nameLabel.bounds.height) / 2,
            width: nameLabel.bounds.width,
            height: nameLabel.bounds.height
        )
        centerOffset = CGPoint(x: bounds.midX - triangleSide / 2, y: 0)
    }

    private static func triangle(selected: Bool) -> UIImage {
        let side: CGFloat = 22
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: side / 2, y: 1))
            path.addLine(to: CGPoint(x: side - 1, y: side - 1))
            path.addLine(to: CGPoint(x: 1, y: side - 1))
            path.close()
            (selected ? SurveyUIColor.amber : UIColor.white).setFill()
            path.fill()
            UIColor.black.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}

final class ReachCircleOverlay: MKCircle {
    var stroke: UIColor = SurveyUIColor.amber
    var fill: UIColor = SurveyUIColor.amber.withAlphaComponent(0.08)
    var lineWidth: CGFloat = 3
}

final class IncidentHeatOverlay: MKCircle {
    var fill: UIColor = SurveyUIColor.red.withAlphaComponent(0.4)
}

final class ReachAreaOverlay: MKPolygon {
    var stroke: UIColor = SurveyUIColor.red
    var fill: UIColor = SurveyUIColor.red.withAlphaComponent(0.22)
}

final class ReachLineOverlay: MKPolyline {
    var stroke: UIColor = SurveyUIColor.red
}

final class CrewAnnotation: NSObject, MKAnnotation {
    let peerID: String
    let role: CrewRole
    let level: ProximityLevel
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let title: String?
    var subtitle: String? { role.label }

    init(peerID: String, role: CrewRole, level: ProximityLevel, coordinate: CLLocationCoordinate2D, name: String) {
        self.peerID = peerID
        self.role = role
        self.level = level
        self.coordinate = coordinate
        self.title = name
        super.init()
    }
}

final class UserDotAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}
