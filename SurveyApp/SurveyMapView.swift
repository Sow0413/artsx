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
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = true
        map.showsTraffic = false
        map.backgroundColor = SurveyUIColor.mapBackdrop
        context.coordinator.attach(field: field, map: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = true
        map.backgroundColor = SurveyUIColor.mapBackdrop
        context.coordinator.attach(field: field, map: map)
        context.coordinator.update(
            map: map,
            reading: field.navigationReading,
            viewport: field.viewport,
            followUser: field.followUser,
            tone: field.badge.tone,
            offlineRevision: field.offlineRevision,
            snap: field.stakeoutCamera
        )
        context.coordinator.syncControls(
            on: map,
            points: field.visibleControlPoints,
            selectedID: field.selectedControlPointID
        )
        context.coordinator.syncTiles(on: map, shown: field.showMapTiles)
        context.coordinator.attachedIndex = field.drawing.mapIndex
        context.coordinator.syncDrawing(
            on: map,
            paths: field.drawing.mapPaths,
            revision: field.drawing.mapRevision,
            shown: field.showDrawing
        )
        context.coordinator.syncReach(on: map, field: field)
        context.coordinator.syncCrew(on: map, field: field)
        context.coordinator.syncAid(on: map, field: field)
        context.coordinator.syncDisaster(on: map, field: field)
        context.coordinator.syncHeat(on: map, field: field)
        context.coordinator.setMapPick(field.drawing.pick == .mapPoint) { latitude, longitude in
            field.completeDrawingMapPick(latitude: latitude, longitude: longitude)
        }
        context.coordinator.setCadTap { latitude, longitude, free in
            field.handleMapTap(latitude: latitude, longitude: longitude, free: free)
        }
        context.coordinator.syncCad(
            on: map,
            target: field.cadPick,
            user: field.cadStaking ? field.navigationReading.position : nil,
            close: field.cadStaking && (field.cadDistanceMeters ?? 10) < 1
        )
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
        private var drawingLines: [MKOverlay] = []
        private var drawingColors: [ObjectIdentifier: UIColor] = [:]
        var attachedIndex = DrawingMapIndex.empty
        private var drawingRevision = -1
        private var drawingShown = true
        private var drawingZoom = -1
        private var lastDrawingPaths: [GeographicPath] = []
        private var drawingBuffer: GeoBounds?
        private var drawingPixel = 0.0
        private var drawingCull: DispatchWorkItem?
        private var drawingCullID = 0
        private var reachOverlays: [MKOverlay] = []
        private var reachKey = ""
        private var crewOverlays: [MKOverlay] = []
        private var crewAnnotations: [CrewAnnotation] = []
        private var crewKey = ""
        private var aidAnnotations: [AidAnnotation] = []
        private var aidKey = ""
        private var disasterAnnotations: [MKAnnotation] = []
        private var disasterOverlays: [MKOverlay] = []
        private var disasterKey = ""
        private var heatOverlays: [MKOverlay] = []
        private var heatKey = ""
        private var mapPick = false
        private var onMapTap: (Double, Double) -> Void = { _, _ in }
        private var onCadTap: ((Double, Double, Bool) -> Void)?
        private var cadLine: MKPolyline?
        private var cadCircle: MKCircle?
        private var cadInner: MKCircle?
        private var cadCross: CadCrosshairAnnotation?
        private var cadArrow: CadArrowAnnotation?

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
                let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
                press.minimumPressDuration = 0.45
                map.addGestureRecognizer(press)
            }
        }

        func setCadTap(_ handler: @escaping (Double, Double, Bool) -> Void) {
            onCadTap = handler
        }

        func setMapPick(_ enabled: Bool, handler: @escaping (Double, Double) -> Void) {
            mapPick = enabled
            onMapTap = handler
        }

        func syncReach(on map: MKMapView, field: FieldModel) {
            let position = field.navigationReading.position
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
            guard field.extras.proximity else {
                if !crewOverlays.isEmpty {
                    map.removeOverlays(crewOverlays)
                    crewOverlays = []
                }
                if !crewAnnotations.isEmpty {
                    map.removeAnnotations(crewAnnotations)
                    crewAnnotations = []
                }
                crewKey = ""
                return
            }
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

        func syncAid(on map: MKMapView, field: FieldModel) {
            let arrows = field.extras.firstResponse ? field.aidArrows : []
            let key = arrows.map { "\($0.id):\($0.latitudeDegrees):\($0.longitudeDegrees):\($0.text)" }.joined(separator: "|")
            if key == aidKey { return }
            aidKey = key
            if !aidAnnotations.isEmpty {
                map.removeAnnotations(aidAnnotations)
                aidAnnotations = []
            }
            for arrow in arrows {
                let mark = AidAnnotation(
                    pointID: arrow.id,
                    coordinate: CLLocationCoordinate2D(latitude: arrow.latitudeDegrees, longitude: arrow.longitudeDegrees),
                    title: arrow.text
                )
                aidAnnotations.append(mark)
            }
            if !aidAnnotations.isEmpty {
                map.addAnnotations(aidAnnotations)
            }
        }

        func syncDisaster(on map: MKMapView, field: FieldModel) {
            guard field.extras.disaster else {
                if !disasterAnnotations.isEmpty {
                    map.removeAnnotations(disasterAnnotations)
                    disasterAnnotations = []
                }
                if !disasterOverlays.isEmpty {
                    map.removeOverlays(disasterOverlays)
                    disasterOverlays = []
                }
                disasterKey = ""
                return
            }
            let crewIDs = Set(field.crew.peers.map(\.id))
            let peers = field.disasterPeers.filter { !crewIDs.contains($0.deviceID) && $0.deviceID != field.crew.deviceID }
            let key = field.disasterSites.map { "\($0.id.uuidString):\($0.latitudeDegrees):\($0.longitudeDegrees)" }.joined(separator: "|")
                + "#"
                + field.disasterSegments.map { segment in
                    let points = segment.points.map { "\($0.latitudeDegrees),\($0.longitudeDegrees)" }.joined(separator: ";")
                    return "\(segment.author):\(segment.state.rawValue):\(points)"
                }.joined(separator: "|")
                + "#"
                + peers.map { "\($0.deviceID):\($0.latitudeDegrees):\($0.longitudeDegrees)" }.joined(separator: "|")
            if key == disasterKey { return }
            disasterKey = key
            if !disasterAnnotations.isEmpty {
                map.removeAnnotations(disasterAnnotations)
                disasterAnnotations = []
            }
            if !disasterOverlays.isEmpty {
                map.removeOverlays(disasterOverlays)
                disasterOverlays = []
            }
            for site in field.disasterSites {
                disasterAnnotations.append(DisasterSiteAnnotation(site: site))
            }
            for position in peers {
                disasterAnnotations.append(DisasterPeerAnnotation(position: position))
            }
            for segment in field.disasterSegments {
                if segment.points.count >= 2 {
                    var coordinates = segment.points.map {
                        CLLocationCoordinate2D(latitude: $0.latitudeDegrees, longitude: $0.longitudeDegrees)
                    }
                    let line = ReachLineOverlay(coordinates: &coordinates, count: coordinates.count)
                    line.stroke = segment.state == .open ? SurveyUIColor.green : SurveyUIColor.red
                    disasterOverlays.append(line)
                }
                if (segment.points.count == 1 || segment.state == .closed), let point = segment.points.last {
                    disasterAnnotations.append(PassageMarkAnnotation(point: point, state: segment.state, author: segment.author))
                }
            }
            if !disasterAnnotations.isEmpty {
                map.addAnnotations(disasterAnnotations)
            }
            if !disasterOverlays.isEmpty {
                map.addOverlays(disasterOverlays, level: .aboveLabels)
            }
        }

        private static func disasterColor(_ kind: DisasterKind) -> UIColor {
            switch kind {
            case .collapse, .roadCut: return SurveyUIColor.red
            case .flood: return SurveyUIColor.blue
            case .bridge, .sediment: return SurveyUIColor.amber
            case .other: return SurveyUIColor.grey
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

        func syncTiles(on map: MKMapView, shown: Bool) {
            if !shown {
                if let tileOverlay {
                    map.removeOverlay(tileOverlay)
                    self.tileOverlay = nil
                }
                return
            }
            if tileOverlay == nil {
                installTiles(on: map)
            }
        }

        func syncDrawing(on map: MKMapView, paths: [GeographicPath], revision: Int, shown: Bool) {
            lastDrawingPaths = paths
            guard revision != drawingRevision || shown != drawingShown else { return }
            drawingRevision = revision
            drawingShown = shown
            drawingBuffer = nil
            drawingCull?.cancel()
            replaceDrawing(paths, on: map)
        }

        func scheduleDrawingCull(on map: MKMapView) {
            guard drawingShown else { return }
            drawingCull?.cancel()
            let work = DispatchWorkItem { [weak self, weak map] in
                guard let self, let map else { return }
                self.cullDrawing(on: map)
            }
            drawingCull = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        private func cullDrawing(on map: MKMapView) {
            let region = map.region
            let visible = GeoBounds(
                south: region.center.latitude - region.span.latitudeDelta / 2,
                west: region.center.longitude - region.span.longitudeDelta / 2,
                north: region.center.latitude + region.span.latitudeDelta / 2,
                east: region.center.longitude + region.span.longitudeDelta / 2
            )
            let width = Double(max(map.bounds.width, 1))
            let latitude = region.center.latitude * .pi / 180
            let metersPerPixel = region.span.longitudeDelta * 111_320 * max(0.2, abs(cos(latitude))) / width
            if let drawingBuffer, DrawingMapIndex.contains(inner: visible, in: drawingBuffer),
               drawingPixel > 0, abs(metersPerPixel - drawingPixel) / drawingPixel < 0.25 {
                return
            }
            let index = attachedIndex
            guard index.bounds != nil else { return }
            let buffer = DrawingMapIndex.buffer(
                south: visible.south,
                west: visible.west,
                north: visible.north,
                east: visible.east
            )
            drawingCullID += 1
            let ticket = drawingCullID
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak map] in
                let query = index.paths(
                    south: buffer.south,
                    west: buffer.west,
                    north: buffer.north,
                    east: buffer.east,
                    metersPerPixel: metersPerPixel
                )
                DispatchQueue.main.async {
                    guard let self, let map, ticket == self.drawingCullID else { return }
                    self.drawingBuffer = buffer
                    self.drawingPixel = metersPerPixel
                    self.replaceDrawing(query.paths, on: map)
                }
            }
        }

        private func replaceDrawing(_ paths: [GeographicPath], on map: MKMapView) {
            if !drawingLines.isEmpty {
                map.removeOverlays(drawingLines)
            }
            drawingLines = []
            drawingColors = [:]
            guard drawingShown else { return }
            var groups: [String: (UIColor, [MKPolyline])] = [:]
            for path in paths {
                var coordinates = path.coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitudeDegrees, longitude: $0.longitudeDegrees)
                }
                guard coordinates.count >= 2 else { continue }
                let line = MKPolyline(coordinates: &coordinates, count: coordinates.count)
                let key = String(format: "%.3f %.3f %.3f", path.red, path.green, path.blue)
                let color = UIColor(red: path.red, green: path.green, blue: path.blue, alpha: 1)
                var group = groups[key] ?? (color, [])
                group.1.append(line)
                groups[key] = group
            }
            for (_, group) in groups {
                let multi = MKMultiPolyline(group.1)
                drawingColors[ObjectIdentifier(multi)] = group.0
                drawingLines.append(multi)
            }
            if !drawingLines.isEmpty {
                map.addOverlays(drawingLines, level: .aboveLabels)
            }
        }

        private static func meters(_ coordinates: [CLLocationCoordinate2D]) -> Double {
            guard coordinates.count >= 2 else { return 0 }
            var total = 0.0
            for index in 1..<coordinates.count {
                let previous = coordinates[index - 1]
                let next = coordinates[index]
                let north = (next.latitude - previous.latitude) * 111_320
                let east = (next.longitude - previous.longitude) * 111_320 * max(0.2, abs(cos(previous.latitude * .pi / 180)))
                total += (north * north + east * east).squareRoot()
            }
            return total
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            if mapPick { onMapTap(coordinate.latitude, coordinate.longitude) }
            onCadTap?(coordinate.latitude, coordinate.longitude, false)
        }

        @objc func handlePress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let map = gesture.view as? MKMapView else { return }
            let coordinate = map.convert(gesture.location(in: map), toCoordinateFrom: map)
            onCadTap?(coordinate.latitude, coordinate.longitude, true)
        }

        func syncCad(on map: MKMapView, target: CadPick?, user: GeodeticPosition?, close: Bool) {
            if let cadLine { map.removeOverlay(cadLine); self.cadLine = nil }
            if let cadCircle { map.removeOverlay(cadCircle); self.cadCircle = nil }
            if let cadInner { map.removeOverlay(cadInner); self.cadInner = nil }
            if let cadArrow { map.removeAnnotation(cadArrow); self.cadArrow = nil }
            let spot = target.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            if let target, let user, user.isPlottable, let spot {
                let north = (target.latitude - user.latitudeDegrees) * 111_320
                let east = (target.longitude - user.longitudeDegrees) * 111_320 * max(0.2, abs(cos(user.latitudeDegrees * .pi / 180)))
                let meters = (north * north + east * east).squareRoot()
                if meters > 0.05 {
                    var coords = [
                        CLLocationCoordinate2D(latitude: user.latitudeDegrees, longitude: user.longitudeDegrees),
                        spot
                    ]
                    let line = MKPolyline(coordinates: &coords, count: 2)
                    cadLine = line
                    map.addOverlay(line, level: .aboveLabels)
                    let fraction = 0.82
                    let arrow = CadArrowAnnotation()
                    arrow.coordinate = CLLocationCoordinate2D(
                        latitude: user.latitudeDegrees + (target.latitude - user.latitudeDegrees) * fraction,
                        longitude: user.longitudeDegrees + (target.longitude - user.longitudeDegrees) * fraction
                    )
                    arrow.bearingDegrees = atan2(east, north) * 180 / .pi
                    cadArrow = arrow
                    map.addAnnotation(arrow)
                }
            }
            if let spot, close {
                let outer = MKCircle(center: spot, radius: 12)
                let inner = MKCircle(center: spot, radius: 4)
                cadCircle = outer
                cadInner = inner
                map.addOverlay(outer, level: .aboveLabels)
                map.addOverlay(inner, level: .aboveLabels)
            }
            if let spot {
                if cadCross == nil {
                    let mark = CadCrosshairAnnotation()
                    mark.title = "目標"
                    cadCross = mark
                    map.addAnnotation(mark)
                }
                cadCross?.coordinate = spot
            } else if let cadCross {
                map.removeAnnotation(cadCross)
                self.cadCross = nil
            }
        }

        func update(
            map: MKMapView,
            reading: PositionReading,
            viewport: MapViewport,
            followUser: Bool,
            tone: AccuracyTone,
            offlineRevision: Int,
            snap: Bool
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
            guard appliedViewport != viewport else { return }
            appliedViewport = viewport
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: viewport.centerLatitude, longitude: viewport.centerLongitude),
                span: MKCoordinateSpan(latitudeDelta: viewport.latitudeDelta, longitudeDelta: viewport.longitudeDelta)
            )
            applyingProgrammaticRegion = true
            map.setRegion(region, animated: snap ? false : didSetInitialRegion)
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
            scheduleDrawingCull(on: mapView)
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
            if let line = overlay as? MKPolyline, line === cadLine {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = UIColor(red: 0.85, green: 0.12, blue: 0.1, alpha: 1)
                renderer.lineWidth = 4
                renderer.lineCap = .round
                return renderer
            }
            if let circle = overlay as? MKCircle, circle === cadCircle || circle === cadInner {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = .clear
                renderer.strokeColor = UIColor(red: 0.85, green: 0.12, blue: 0.1, alpha: 1)
                renderer.lineWidth = circle === cadInner ? 2 : 4
                return renderer
            }
            if let multi = overlay as? MKMultiPolyline {
                let renderer = MKMultiPolylineRenderer(multiPolyline: multi)
                renderer.strokeColor = drawingColors[ObjectIdentifier(multi)] ?? UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
                renderer.lineWidth = 1
                return renderer
            }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
                renderer.lineWidth = 1
                return renderer
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                let color = tone.circle
                if SurveyColor.outdoor {
                    renderer.fillColor = .clear
                    renderer.strokeColor = color
                    renderer.lineWidth = SurveyColor.stroke
                } else {
                    renderer.fillColor = color.withAlphaComponent(tone == .green ? 0.30 : 0.22)
                    renderer.strokeColor = color
                    renderer.lineWidth = 2
                }
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
            if let site = annotation as? DisasterSiteAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "disaster-site")
                    ?? MKMarkerAnnotationView(annotation: site, reuseIdentifier: "disaster-site")
                view.annotation = site
                if let marker = view as? MKMarkerAnnotationView {
                    marker.markerTintColor = Self.disasterColor(site.kind)
                    marker.glyphText = String(site.kind.label.prefix(1))
                    marker.titleVisibility = .visible
                }
                return view
            }
            if let passage = annotation as? PassageMarkAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "disaster-pass")
                    ?? MKMarkerAnnotationView(annotation: passage, reuseIdentifier: "disaster-pass")
                view.annotation = passage
                if let marker = view as? MKMarkerAnnotationView {
                    marker.markerTintColor = passage.state == .open ? SurveyUIColor.green : SurveyUIColor.red
                    marker.glyphText = passage.state == .open ? "通" : "止"
                    marker.titleVisibility = .visible
                }
                return view
            }
            if let peer = annotation as? DisasterPeerAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "disaster-peer")
                    ?? MKMarkerAnnotationView(annotation: peer, reuseIdentifier: "disaster-peer")
                view.annotation = peer
                if let marker = view as? MKMarkerAnnotationView {
                    marker.markerTintColor = SurveyUIColor.blue
                    marker.glyphText = "人"
                    marker.titleVisibility = .visible
                }
                return view
            }
            if let aid = annotation as? AidAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "aid-pin")
                    ?? MKMarkerAnnotationView(annotation: aid, reuseIdentifier: "aid-pin")
                view.annotation = aid
                if let marker = view as? MKMarkerAnnotationView {
                    marker.markerTintColor = SurveyUIColor.red
                    marker.glyphText = String(aid.title?.prefix(1) ?? "救")
                }
                view.canShowCallout = true
                return view
            }
            if annotation is CadCrosshairAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "cad-cross")
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "cad-cross")
                view.annotation = annotation
                view.image = Self.crosshairImage
                view.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
                view.canShowCallout = false
                return view
            }
            if let arrow = annotation as? CadArrowAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "cad-arrow")
                    ?? MKAnnotationView(annotation: arrow, reuseIdentifier: "cad-arrow")
                view.annotation = arrow
                view.image = Self.arrowImage
                view.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
                view.transform = CGAffineTransform(rotationAngle: arrow.bearingDegrees * .pi / 180)
                view.canShowCallout = false
                return view
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
            guard field.extras.stats, field.showIncidentHeat else {
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

        private static let crosshairImage: UIImage = {
            let size = CGSize(width: 44, height: 44)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let ink = UIColor(red: 0.85, green: 0.12, blue: 0.1, alpha: 1)
                ink.setStroke()
                let line = context.cgContext
                line.setLineWidth(3)
                line.move(to: CGPoint(x: 22, y: 2))
                line.addLine(to: CGPoint(x: 22, y: 42))
                line.move(to: CGPoint(x: 2, y: 22))
                line.addLine(to: CGPoint(x: 42, y: 22))
                line.strokePath()
                line.strokeEllipse(in: CGRect(x: 12, y: 12, width: 20, height: 20))
            }
        }()

        private static let arrowImage: UIImage = {
            let size = CGSize(width: 28, height: 28)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let line = context.cgContext
                line.setFillColor(UIColor(red: 0.85, green: 0.12, blue: 0.1, alpha: 1).cgColor)
                line.move(to: CGPoint(x: 14, y: 2))
                line.addLine(to: CGPoint(x: 26, y: 24))
                line.addLine(to: CGPoint(x: 2, y: 24))
                line.closePath()
                line.fillPath()
            }
        }()

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

final class CadCrosshairAnnotation: MKPointAnnotation {}

final class CadArrowAnnotation: MKPointAnnotation {
    var bearingDegrees: CLLocationDirection = 0
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

final class DrawingStrokeOverlay: MKPolyline {
    var stroke = UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
}

final class ReachLineOverlay: MKPolyline {
    var stroke: UIColor = SurveyUIColor.red
}

final class AidAnnotation: NSObject, MKAnnotation {
    let pointID: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let title: String?

    init(pointID: String, coordinate: CLLocationCoordinate2D, title: String) {
        self.pointID = pointID
        self.coordinate = coordinate
        self.title = title
        super.init()
    }
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
