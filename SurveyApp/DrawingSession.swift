import Combine
import Foundation
import SurveyCore

enum DrawingPick: Equatable {
    case idle
    case drawingVertex
    case mapPoint
}

struct DrawingCamera: Equatable {
    var centerX = 0.0
    var centerY = 0.0
    var pointsPerUnit = 1.0
    var rotationDegrees = 0.0
    var fittedID: String?
}

/// 図面タブの状態。DXF の原本は設計フォルダに置き、合わせは別の版として足す。
final class DrawingSession: ObservableObject {
    @Published private(set) var projects: [SurveyProject] = []
    @Published private(set) var project: SurveyProject?
    @Published private(set) var document: DrawingDocument?
    @Published private(set) var fileName: String?
    @Published var zone = 9
    @Published var axis: DrawingAxis = .cadEastNorth
    @Published private(set) var zoneChoices: [Int] = Array(1...19)
    @Published private(set) var placementNote: String?
    @Published private(set) var warning: ZoneWarning?
    @Published private(set) var suggestion: ZoneSuggestion?
    @Published private(set) var pairs: [AlignmentPair] = []
    @Published var lockScale = false
    @Published private(set) var fit: SimilarityFit?
    @Published private(set) var alignments: [AlignmentRecord] = []
    @Published private(set) var activeAlignmentID: String?
    @Published var alignmentName = "手合わせ"
    @Published private(set) var message: String?
    @Published var pick: DrawingPick = .idle
    @Published private(set) var pending: PlanarPoint?
    @Published private(set) var inspection: DrawingInspect?
    @Published private(set) var mapPaths: [GeographicPath] = []
    @Published private(set) var mapRevision = 0
    @Published private(set) var overlayCapped = false
    @Published var camera = DrawingCamera()
    @Published private(set) var backgroundVerdict: BackgroundVerdict?
    @Published private(set) var backgroundBusy = false
    @Published private(set) var activeRecordFolder: String?
    @Published private(set) var operatorEntityID: Int?
    /// この現場の計画高（床掘底）。無いときはオペ画面に楕円体高を出す。
    @Published var designHeightMeters: Double?
    /// 作業半径。既定は 20t の目安 9m。project.json に保存する。
    @Published private(set) var machineRadiusMeters = MachineCatalog.twentyTon.radiusMeters
    @Published private(set) var machinePresetID: String? = MachineCatalog.twentyTon.id
    /// 地盤または機体から目まで。端末を目の高さで持つときは下がりに足さない。
    @Published private(set) var eyeHeightMeters = 2.0
    @Published private(set) var sightDatum: SightDatum = .ground
    @Published private(set) var phoneAtEyes = true
    /// 測点間隔。既定 20m。
    @Published private(set) var stationIntervalMeters = OperatorStation.intervalMeters
    /// 中心線の始点を No. いくつにするか。
    @Published private(set) var stationOrigin = 0
    /// 追加距離付きの中心線。無いときは測点を出さない。
    @Published private(set) var stationLine: StationLine?

    let projectsRoot: URL
    private var reference: (latitude: Double, longitude: Double, name: String)?
    private var referenceStamp: (latitude: Double, longitude: Double)?

    init(projectsRoot: URL) {
        self.projectsRoot = projectsRoot
        reload()
    }

    var activeTransform: Similarity2D? {
        if pairs.count >= 2 { return fit?.transform }
        return alignments.first { $0.id == activeAlignmentID }?.transform
    }

    var accuracy: AlignmentAccuracy {
        AlignmentAccuracy.decide(pairs.map(\.kind))
    }

    /// 2組以上の手合わせが優先。なければ、使っている合わせの札。cm は座標簿の札だけ。
    var stakeoutAccuracy: AlignmentAccuracy? {
        if pairs.count >= 2 { return AlignmentAccuracy.decide(pairs.map(\.kind)) }
        if pairs.isEmpty {
            return alignments.first { $0.id == activeAlignmentID }?.accuracyTag
        }
        return nil
    }

    var activeComposesAxis: Bool {
        if pairs.count >= 2 { return false }
        return alignments.first { $0.id == activeAlignmentID }?.composesAxis ?? false
    }

    func reload() {
        projects = (try? ProjectStore.list(at: projectsRoot)) ?? []
    }

    func createProject(named rawName: String) {
        do {
            let created = try ProjectStore.create(name: rawName, at: projectsRoot)
            reload()
            select(created)
            message = "\(created.name) を作りました。"
        } catch let error as ProjectStoreError {
            message = error.description
        } catch {
            message = "プロジェクトを作れませんでした。"
        }
    }

    func select(_ selected: SurveyProject) {
        project = selected
        zone = selected.zone ?? zone
        axis = selected.axis
        alignments = (try? ProjectStore.alignments(projectName: selected.name, at: projectsRoot)) ?? []
        pairs = []
        fit = nil
        pending = nil
        inspection = nil
        activeAlignmentID = alignments.last?.id
        if let active = alignments.last {
            pairs = active.pairs
            lockScale = active.lockScale
            zone = active.zone
            axis = active.axis
        }
        if let drawing = selected.drawings.last,
           let data = try? ProjectStore.originalDXF(fileName: drawing.fileName, projectName: selected.name, at: projectsRoot) {
            applyParsed(data, fileName: drawing.fileName)
        } else {
            document = nil
            fileName = nil
            camera.fittedID = nil
        }
        applyCab(from: selected)
        refresh()
        refreshPlacement(latitude: nil, longitude: nil, overrideZone: false)
    }

    func importFile(
        data: Data,
        fileName rawName: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        guard var current = project else {
            message = "先にプロジェクトを作ってください。"
            return
        }
        do {
            let ext = (rawName as NSString).pathExtension.lowercased()
            let parsed: DrawingDocument
            if ext == "sfc" {
                parsed = try SFCParser.parse(data)
                axis = .cadEastNorth
                current.axis = .cadEastNorth
            } else {
                parsed = try DXFParser.parse(data)
            }
            let stored = try ProjectStore.importDXF(
                data: data,
                fileName: rawName,
                into: &current,
                at: projectsRoot,
                codePage: parsed.codePage,
                unsupported: parsed.unsupportedCounts
            )
            project = current
            reload()
            document = parsed
            fileName = stored
            camera.fittedID = nil
            backgroundVerdict = nil
            var note = ext == "sfc"
                ? "設計に \(stored) を置きました。公共座標として読みました。系を選ぶと地図に載ります。元の SFC は変えていません。"
                : "設計に \(stored) を置きました。元の DXF は変えていません。"
            if let unit = parsed.unitWarning, ext != "sfc" { note += unit }
            if !parsed.unsupportedSummary.isEmpty { note += "読めない要素: \(parsed.unsupportedSummary)。" }
            message = note
            refreshPlacement(latitude: latitude, longitude: longitude, overrideZone: ext == "sfc")
            if let placementNote {
                message = [message, placementNote].compactMap { $0 }.joined(separator: " ")
            }
            refresh()
        } catch let error as DXFError {
            message = error.description
        } catch let error as SFCError {
            message = error.description
        } catch {
            message = "図面を読めませんでした。"
        }
    }

    func setPrefecture(_ raw: String?, latitude: Double?, longitude: Double?) {
        let name = raw.flatMap { PlaneZoneCatalog.named($0)?.name }
        project?.prefecture = name
        persistProject()
        refreshPlacement(latitude: latitude, longitude: longitude, overrideZone: true)
    }

    func setZone(_ number: Int) {
        guard PlaneRectangular.zone(number) != nil else { return }
        zone = number
        project?.zone = number
        persistProject()
        refresh()
        rebuildStationLine()
    }

    func refreshPlacement(latitude: Double?, longitude: Double?, overrideZone: Bool) {
        guard let document, !document.bounds.isEmpty else {
            if let name = project?.prefecture, let record = PlaneZoneCatalog.named(name) {
                zoneChoices = record.zones
                placementNote = record.decidesZone
                    ? "\(record.name)は\(record.zones[0])系です。"
                    : "\(record.name)は\(record.zones.map { "\($0)系" }.joined(separator: "・"))です。"
            }
            return
        }
        let placement = PlanePlacementChooser.choose(
            x: document.bounds.midX,
            y: document.bounds.midY,
            prefecture: project?.prefecture,
            latitude: latitude,
            longitude: longitude
        )
        var choices = placement.zones
        if !choices.contains(zone) { choices.append(zone) }
        zoneChoices = choices.sorted()
        placementNote = placement.note
        guard overrideZone else { return }
        if let decided = placement.decidedZone, PlaneRectangular.zone(decided) != nil {
            zone = decided
            project?.zone = decided
        }
        if let decided = placement.decidedAxis {
            axis = decided
            project?.axis = decided
        }
        persistProject()
        refresh()
    }

    func setAxis(_ next: DrawingAxis) {
        axis = next
        project?.axis = next
        persistProject()
        refresh()
        rebuildStationLine()
    }

    func toggleLayer(_ name: String, visible: Bool) {
        document = document?.settingLayer(name, visible: visible)
        refreshMap()
    }

    func setRole(_ role: DrawingLayerRole, visible: Bool) {
        document = document?.settingRole(role, visible: visible)
        refreshMap()
    }

    func operatorGuide(at position: GeodeticPosition?) -> OperatorGuide? {
        guard let position, position.isPlottable else { return nil }
        if let stationLine {
            return stationLine.locate(latitudeDegrees: position.latitudeDegrees, longitudeDegrees: position.longitudeDegrees)
        }
        guard let alignment = operatorPlaneLine(), alignment.count >= 2 else { return nil }
        guard let plane = PlaneRectangular.forward(
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            zone: zone
        ) else { return nil }
        let here = PlanarPoint(x: plane.eastingMeters, y: plane.northingMeters)
        return OperatorStation.guide(
            point: here,
            alignment: alignment,
            interval: stationIntervalMeters,
            originStation: stationOrigin
        )
    }

    func setDesignHeight(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        designHeightMeters = trimmed.isEmpty ? nil : Double(trimmed)
    }

    func setMachineRadius(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value >= 0.5, value <= 200 else {
            message = "作業半径は 0.5m から 200m です。"
            return
        }
        let rounded = MachineReach.roundTenths(value)
        machineRadiusMeters = rounded
        machinePresetID = MachineCatalog.presets.first { abs($0.radiusMeters - rounded) < 0.05 }?.id
        storeCab()
        message = "作業半径を \(String(format: "%.1f", rounded))m にしました。"
    }

    func selectMachinePreset(_ id: String?) {
        if let id, let preset = MachineCatalog.named(id) {
            machinePresetID = preset.id
            machineRadiusMeters = preset.radiusMeters
            message = "\(preset.label) の作業半径 \(String(format: "%.0f", preset.radiusMeters))m（目安）にしました。"
        } else {
            machinePresetID = nil
            message = "作業半径は手入力です。"
        }
        storeCab()
    }

    func setEyeHeight(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value >= 0, value <= 20 else {
            message = "視線高は 0m から 20m です。"
            return
        }
        eyeHeightMeters = MachineReach.roundTenths(value)
        storeCab()
    }

    func setSightDatum(_ datum: SightDatum) {
        sightDatum = datum
        storeCab()
    }

    func setPhoneAtEyes(_ atEyes: Bool) {
        phoneAtEyes = atEyes
        storeCab()
    }

    /// 図面のタップ、無ければ選んだ基準点を目標にする。
    func operatorTarget(control: ControlPoint?) -> (latitude: Double, longitude: Double)? {
        if let inspection, let latitude = inspection.latitudeDegrees, let longitude = inspection.longitudeDegrees {
            return (latitude, longitude)
        }
        if let control {
            return (control.latitudeDegrees, control.longitudeDegrees)
        }
        return nil
    }

    func reachGraphics(latitude: Double, longitude: Double) -> (center: PlanarPoint, radius: Double, ranges: [ReachRange], rings: [ReachRing])? {
        guard let placed = DrawingPlacement.user(
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            horizontalAccuracyMeters: 1,
            zone: zone,
            axis: axis,
            transform: activeTransform,
            composesAxis: activeComposesAxis
        ) else { return nil }
        let scale = abs(activeTransform?.scale ?? 1)
        let radius = machineRadiusMeters / max(scale, 1e-9)
        let ranges = excavationRanges(center: placed.point, radius: radius)
        let rings = ranges.compactMap { range -> ReachRing? in
            let coordinates = range.points.compactMap {
                DrawingPlacement.geographic($0, zone: zone, axis: axis, transform: activeTransform, composesAxis: activeComposesAxis)
            }
            guard coordinates.count >= 2, coordinates.count == range.points.count else { return nil }
            let closed = coordinates.count >= 3
            return ReachRing(coordinates: coordinates, coverage: range.coverage, closed: closed)
        }
        return (placed.point, radius, ranges, rings)
    }

    private func excavationRanges(center: PlanarPoint, radius: Double) -> [ReachRange] {
        guard let document else { return [] }
        return document.entities.compactMap { entity in
            guard isExcavation(entity, in: document) else { return nil }
            let points = entity.stroke
            guard points.count >= 2 else { return nil }
            let coverage = MachineReach.coverage(of: points, closed: false, center: center, radius: radius)
            return ReachRange(points: points, coverage: coverage)
        }
    }

    private func isExcavation(_ entity: DrawingEntity, in document: DrawingDocument) -> Bool {
        guard entity.stroke.count >= 2 else { return false }
        let name = entity.layer
        if name.contains("掘削") || name.contains("床掘") || name.contains("法面") { return true }
        let role = document.layers.first { $0.name == entity.layer }?.role
        guard role == .design else { return false }
        switch entity.primitive {
        case let .polyline(_, closed, _):
            return closed
        case .circle:
            return true
        default:
            return false
        }
    }

    private func applyCab(from project: SurveyProject) {
        if let radius = project.machineRadiusMeters, radius > 0 {
            machineRadiusMeters = radius
        } else {
            machineRadiusMeters = MachineCatalog.twentyTon.radiusMeters
        }
        if let preset = project.machinePreset, MachineCatalog.named(preset) != nil {
            machinePresetID = preset
        } else if project.machineRadiusMeters == nil {
            machinePresetID = MachineCatalog.twentyTon.id
        } else {
            machinePresetID = nil
        }
        if let eye = project.eyeHeightMeters, eye >= 0 {
            eyeHeightMeters = eye
        } else {
            eyeHeightMeters = 2
        }
        sightDatum = project.sightDatum ?? .ground
        phoneAtEyes = project.phoneAtEyes ?? true
        if let interval = project.stationIntervalMeters, interval > 0 {
            stationIntervalMeters = interval
        } else {
            stationIntervalMeters = OperatorStation.intervalMeters
        }
        stationOrigin = project.stationOrigin ?? 0
        stationLine = project.stationLine
    }

    private func storeCab() {
        guard var current = project else { return }
        current.machineRadiusMeters = machineRadiusMeters
        current.machinePreset = machinePresetID
        current.eyeHeightMeters = eyeHeightMeters
        current.sightDatum = sightDatum
        current.phoneAtEyes = phoneAtEyes
        project = current
        persistProject()
    }

    private func operatorPlaneLine() -> [PlanarPoint]? {
        guard let operatorEntityID else { return nil }
        return planeVertices(entityID: operatorEntityID)
    }

    private func planeVertices(entityID: Int) -> [PlanarPoint]? {
        guard let document, let entity = document.entities.first(where: { $0.id == entityID }) else { return nil }
        let plane = entity.stroke.compactMap { vertex -> PlanarPoint? in
            planePoint(vertex)
        }
        return plane.count >= 2 ? plane : nil
    }

    private func planePoint(_ point: PlanarPoint) -> PlanarPoint? {
        guard let geo = DrawingPlacement.geographic(
            point,
            zone: zone,
            axis: axis,
            transform: activeTransform,
            composesAxis: activeComposesAxis
        ), let projected = PlaneRectangular.forward(
            latitudeDegrees: geo.latitudeDegrees,
            longitudeDegrees: geo.longitudeDegrees,
            zone: zone
        ) else { return nil }
        return PlanarPoint(x: projected.eastingMeters, y: projected.northingMeters)
    }

    private func stationLabels(near vertices: [PlanarPoint]) -> [StationAnchor] {
        guard let document else { return [] }
        var labels: [StationAnchor] = []
        for entity in document.entities {
            guard case let .text(origin, string, _, _) = entity.primitive else { continue }
            guard StationName.chainageMeters(in: string, interval: stationIntervalMeters) != nil else { continue }
            guard let plane = planePoint(origin) else { continue }
            guard let hit = OperatorStation.project(plane, onto: vertices), abs(hit.offset) <= 40 else { continue }
            labels.append(StationAnchor(name: string, point: plane))
        }
        return labels
    }

    private func verticesLength(_ vertices: [PlanarPoint]) -> Double {
        guard vertices.count >= 2 else { return 0 }
        return OperatorStation.geometricChainage(vertices).last ?? 0
    }

    private func rebuildStationLine() {
        guard let existing = stationLine else { return }
        switch existing.source {
        case .polyline:
            guard let operatorEntityID, let vertices = planeVertices(entityID: operatorEntityID) else { return }
            stationLine = StationLine.polyline(
                vertices: vertices,
                zone: zone,
                intervalMeters: stationIntervalMeters,
                originStation: stationOrigin,
                name: existing.name,
                anchors: stationLabels(near: vertices),
                id: existing.id
            )
        case .anchors:
            guard let project else { return }
            let entries = ProjectStore.coordinateBookEntries(projectName: project.name, at: projectsRoot)
            let anchors = entries.compactMap { entry -> StationAnchor? in
                guard StationName.chainageMeters(in: entry.name, interval: stationIntervalMeters) != nil else { return nil }
                guard let plane = PlaneRectangular.forward(
                    latitudeDegrees: entry.latitudeDegrees,
                    longitudeDegrees: entry.longitudeDegrees,
                    zone: zone
                ) else { return nil }
                return StationAnchor(name: entry.name, point: PlanarPoint(x: plane.eastingMeters, y: plane.northingMeters))
            }.sorted { left, right in
                let leftChain = StationName.chainageMeters(in: left.name, interval: stationIntervalMeters) ?? 0
                let rightChain = StationName.chainageMeters(in: right.name, interval: stationIntervalMeters) ?? 0
                return leftChain < rightChain
            }
            if let rebuilt = StationLine.namedPoints(
                anchors: anchors,
                zone: zone,
                intervalMeters: stationIntervalMeters,
                originStation: stationOrigin,
                name: existing.name,
                id: existing.id
            ) {
                stationLine = rebuilt
            }
        }
    }

    private func storeStation() {
        guard var current = project else { return }
        current.stationIntervalMeters = stationIntervalMeters
        current.stationOrigin = stationOrigin
        current.stationLine = stationLine
        project = current
        persistProject()
    }

    private func nearestLineID(to point: PlanarPoint) -> Int? {
        guard let document else { return nil }
        var best: (id: Int, distance: Double)?
        for entity in document.entities {
            let stroke = entity.stroke
            guard stroke.count >= 2 else { continue }
            for index in 0..<(stroke.count - 1) {
                let distance = distanceToSegment(point, stroke[index], stroke[index + 1])
                if best == nil || distance < best!.distance {
                    best = (entity.id, distance)
                }
            }
        }
        return best?.id
    }

    private func strokeLength(_ entity: DrawingEntity) -> Double {
        let stroke = entity.stroke
        guard stroke.count >= 2 else { return 0 }
        var total = 0.0
        for index in 0..<(stroke.count - 1) {
            total += stroke[index].distance(to: stroke[index + 1])
        }
        return total
    }

    private func distanceToSegment(_ point: PlanarPoint, _ start: PlanarPoint, _ end: PlanarPoint) -> Double {
        let vx = end.x - start.x
        let vy = end.y - start.y
        let lengthSquared = vx * vx + vy * vy
        if lengthSquared < 1e-12 { return point.distance(to: start) }
        var t = ((point.x - start.x) * vx + (point.y - start.y) * vy) / lengthSquared
        if t < 0 { t = 0 }
        if t > 1 { t = 1 }
        return point.distance(to: PlanarPoint(x: start.x + t * vx, y: start.y + t * vy))
    }

    func report(_ text: String) {
        message = text
    }

    func beginMapPick() -> Bool {
        guard pending != nil else {
            message = "先に図面の点をタップしてください。"
            return false
        }
        pick = .mapPoint
        return true
    }

    func beginVertexPick() {
        pick = .drawingVertex
        inspection = nil
        message = "対応づける図面の点をタップしてください。"
    }

    func cancelPick() {
        pick = .idle
        pending = nil
    }

    func takeDrawingTap(_ point: PlanarPoint, tolerance: Double) {
        guard let document else { return }
        guard let hit = DrawingSnap.nearest(in: document, to: point, tolerance: tolerance) else {
            message = "交点・端点・点の近くをタップしてください。"
            return
        }
        if pick == .drawingVertex {
            pending = hit.point
            pick = .idle
            message = "対応する場所を、地図・現在地・座標簿から選んでください。"
            return
        }
        inspection = DrawingPlacement.inspect(
            point: hit.point,
            zone: zone,
            axis: axis,
            transform: activeTransform,
            fromLatitude: reference?.latitude,
            fromLongitude: reference?.longitude,
            composesAxis: activeComposesAxis,
            snapLabel: hit.kind.label
        )
    }

    func setStationInterval(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value >= 1, value <= 1000 else {
            message = "測点間隔は 1m から 1000m です。"
            return
        }
        stationIntervalMeters = MachineReach.roundTenths(value)
        rebuildStationLine()
        storeStation()
        message = "測点間隔を \(String(format: "%.1f", stationIntervalMeters))m にしました。"
    }

    func setStationOrigin(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), value >= 0, value <= 9999 else {
            message = "起点の測点番号は 0 から 9999 です。"
            return
        }
        stationOrigin = value
        rebuildStationLine()
        storeStation()
        message = "起点を No.\(value) にしました。"
    }

    func adoptOperatorLine() {
        guard let inspection else {
            message = "先に図面の線をタップしてください。"
            return
        }
        let tapped = PlanarPoint(x: inspection.drawingX, y: inspection.drawingY)
        operatorEntityID = nearestLineID(to: tapped)
        guard let operatorEntityID, let vertices = planeVertices(entityID: operatorEntityID) else {
            message = "線が見つかりません。"
            return
        }
        let labels = stationLabels(near: vertices)
        guard let line = StationLine.polyline(
            vertices: vertices,
            zone: zone,
            intervalMeters: stationIntervalMeters,
            originStation: stationOrigin,
            anchors: labels
        ) else {
            message = "中心線にできませんでした。"
            return
        }
        stationLine = line
        storeStation()
        let length = String(format: "%.0f", verticesLength(vertices))
        message = labels.isEmpty
            ? "中心線にしました。追加距離 \(length)m。起点は No.\(stationOrigin) です。"
            : "中心線にしました。近くの測点名 \(labels.count) 個で追加距離を張りました。"
    }

    /// 座標簿のうち、No.23 や No.23+5 の名前の点を順につないで中心線にする。
    func adoptNamedStations() {
        guard let project else {
            message = "先にプロジェクトを作ってください。"
            return
        }
        let entries = ProjectStore.coordinateBookEntries(projectName: project.name, at: projectsRoot)
        let anchors = entries.compactMap { entry -> StationAnchor? in
            guard StationName.chainageMeters(in: entry.name, interval: stationIntervalMeters) != nil else { return nil }
            guard let plane = PlaneRectangular.forward(
                latitudeDegrees: entry.latitudeDegrees,
                longitudeDegrees: entry.longitudeDegrees,
                zone: zone
            ) else { return nil }
            return StationAnchor(name: entry.name, point: PlanarPoint(x: plane.eastingMeters, y: plane.northingMeters))
        }.sorted { left, right in
            let leftChain = StationName.chainageMeters(in: left.name, interval: stationIntervalMeters) ?? 0
            let rightChain = StationName.chainageMeters(in: right.name, interval: stationIntervalMeters) ?? 0
            return leftChain < rightChain
        }
        guard let line = StationLine.namedPoints(
            anchors: anchors,
            zone: zone,
            intervalMeters: stationIntervalMeters,
            originStation: stationOrigin
        ) else {
            message = "測点名の点が2つ以上要ります。名前は No.23 や No.23+5 です。"
            return
        }
        operatorEntityID = nil
        stationLine = line
        storeStation()
        message = "測点 \(anchors.count) 点を中心線にしました。追加距離 \(String(format: "%.0f", abs(line.lengthMeters)))m。"
    }

    func addTarget(kind: AlignmentTargetKind, latitude: Double, longitude: Double, label: String) {
        guard let pending else {
            message = "先に図面の点をタップしてください。"
            return
        }
        pairs.append(AlignmentPair(
            drawingX: pending.x,
            drawingY: pending.y,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            kind: kind,
            label: label
        ))
        self.pending = nil
        pick = .idle
        refresh()
        message = pairs.count < 2 ? "もう1組、図面の点を選んでください。" : "対応は \(pairs.count) 組です。"
    }

    func removePair(_ id: String) {
        pairs.removeAll { $0.id == id }
        refresh()
    }

    func setLockScale(_ locked: Bool) {
        lockScale = locked
        refresh()
    }

    func saveAlignment() {
        guard let project, let fileName else {
            message = "先に図面を読み込んでください。"
            return
        }
        guard let fit, pairs.count >= 2 else {
            message = "対応は2組以上にしてください。"
            return
        }
        let accuracy = accuracy
        let record = AlignmentRecord(
            name: alignmentName,
            version: 0,
            createdAt: Date(),
            zone: zone,
            axis: axis,
            lockScale: lockScale,
            transform: fit.transform,
            pairs: pairs,
            residualsMeters: fit.residualsMeters,
            rmsMeters: fit.rmsMeters,
            accuracyTag: accuracy,
            stakeoutNotice: accuracy.notice,
            drawingFileName: fileName
        )
        do {
            let stored = try ProjectStore.saveAlignment(record, projectName: project.name, at: projectsRoot)
            alignments = (try? ProjectStore.alignments(projectName: project.name, at: projectsRoot)) ?? alignments
            activeAlignmentID = stored.id
            message = "合わせ「\(stored.name)」の版 \(stored.version) を設計に置きました。元の図面は変えていません。"
        } catch let error as ProjectStoreError {
            message = error.description
        } catch {
            message = "合わせを保存できませんでした。"
        }
    }

    func use(_ record: AlignmentRecord) {
        activeAlignmentID = record.id
        zone = record.zone
        axis = record.axis
        lockScale = record.lockScale
        pairs = record.pairs
        alignmentName = record.name
        project?.zone = record.zone
        project?.axis = record.axis
        persistProject()
        refresh()
    }

    @discardableResult
    func addFieldRecord(date: String, kind: String, name: String, pointPrefix: String? = nil) -> String? {
        guard let project else {
            message = "先にプロジェクトを作ってください。"
            return nil
        }
        do {
            let note = try ProjectStore.addRecord(
                date: date,
                kind: kind,
                name: name,
                projectName: project.name,
                at: projectsRoot,
                pointPrefix: pointPrefix
            )
            activeRecordFolder = note.folderName
            message = "記録 \(note.folderName) を作りました。"
            return note.folderName
        } catch let error as ProjectStoreError {
            message = error.description
        } catch {
            message = "記録を作れませんでした。"
        }
        return nil
    }

    func checkBackground() {
        guard let document else {
            message = "先に図面を読み込んでください。"
            return
        }
        guard document.has(.background) else {
            message = "背景レイヤがありません。地形・背景・BGD などの名前だけを地理院ベクトルと照合します。"
            return
        }
        backgroundBusy = true
        message = "地理院ベクトルと照合しています。"
        let zone = zone
        let axis = axis
        let snapshot = document
        Task {
            do {
                let reference = try await GSIVectorFetch.reference(document: snapshot, zone: zone)
                let verdict = BackgroundChecker.judge(document: snapshot, reference: reference, currentAxis: axis)
                await MainActor.run {
                    self.backgroundVerdict = verdict
                    self.backgroundBusy = false
                    self.message = verdict.message
                }
            } catch {
                await MainActor.run {
                    self.backgroundBusy = false
                    self.backgroundVerdict = nil
                    self.message = "地理院ベクトルを取れませんでした。"
                }
            }
        }
    }

    func applyBackgroundAlignment() {
        guard var current = project, let fileName, let verdict = backgroundVerdict,
              case let .shifted(_, _, transform, rms) = verdict.outcome else {
            message = "自動で合わせるずれはありません。"
            return
        }
        axis = verdict.axis
        current.axis = verdict.axis
        project = current
        pairs = []
        fit = nil
        pending = nil
        let record = AlignmentRecord(
            name: "背景合わせ",
            version: 0,
            createdAt: Date(),
            zone: zone,
            axis: verdict.axis,
            lockScale: true,
            transform: transform,
            pairs: [],
            residualsMeters: [],
            rmsMeters: rms,
            accuracyTag: .mapGrade,
            stakeoutNotice: AlignmentAccuracy.stakeoutNotice,
            drawingFileName: fileName,
            composesAxis: true
        )
        do {
            let stored = try ProjectStore.saveAlignment(record, projectName: current.name, at: projectsRoot)
            alignments = (try? ProjectStore.alignments(projectName: current.name, at: projectsRoot)) ?? alignments
            activeAlignmentID = stored.id
            persistProject()
            refresh()
            message = "背景のずれで合わせました。札は\(AlignmentAccuracy.mapGrade.rawValue)です。\(AlignmentAccuracy.stakeoutNotice)"
        } catch let error as ProjectStoreError {
            message = error.description
        } catch {
            message = "合わせを保存できませんでした。"
        }
    }

    func noteReference(latitude: Double, longitude: Double, name: String) {
        if let previous = referenceStamp, reference?.name == name,
           let gap = GRS80Geodesic.inverse(
            latitude1: previous.latitude,
            longitude1: previous.longitude,
            latitude2: latitude,
            longitude2: longitude
           ), gap.distanceMeters < 30 {
            return
        }
        reference = (latitude, longitude, name)
        referenceStamp = (latitude, longitude)
        refreshWarning()
        if inspection != nil, let point = inspectionPoint {
            inspection = DrawingPlacement.inspect(
                point: point,
                zone: zone,
                axis: axis,
                transform: activeTransform,
                fromLatitude: latitude,
                fromLongitude: longitude,
                composesAxis: activeComposesAxis,
                snapLabel: inspection?.snapLabel
            )
        }
    }

    func fit(in size: CGSize) {
        guard let document, size.width > 1, size.height > 1 else { return }
        let token = "\(project?.id ?? "")-\(fileName ?? "")-\(document.entities.count)"
        guard camera.fittedID != token else { return }
        camera.centerX = document.bounds.isEmpty ? 0 : document.bounds.midX
        camera.centerY = document.bounds.isEmpty ? 0 : document.bounds.midY
        let span = max(document.bounds.width, document.bounds.height, 1)
        camera.pointsPerUnit = Double(min(size.width, size.height)) * 0.82 / span
        camera.rotationDegrees = 0
        camera.fittedID = token
    }

    func showWholeDrawing() {
        camera.fittedID = nil
    }

    private var inspectionPoint: PlanarPoint? {
        guard let inspection else { return nil }
        return PlanarPoint(x: inspection.drawingX, y: inspection.drawingY)
    }

    private func applyParsed(_ data: Data, fileName: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let parsed = ext == "sfc" ? (try? SFCParser.parse(data)) : (try? DXFParser.parse(data))
        guard let parsed else {
            message = ext == "sfc" ? "保存してある SFC を読めませんでした。" : "保存してある DXF を読めませんでした。"
            return
        }
        document = parsed
        self.fileName = fileName
        camera.fittedID = nil
        backgroundVerdict = nil
    }

    private func persistProject() {
        guard let project else { return }
        try? ProjectStore.save(project, at: projectsRoot)
        if let fileName {
            try? ProjectStore.writeZoneTag(
                for: fileName,
                zone: zone,
                axis: axis,
                projectName: project.name,
                at: projectsRoot
            )
        }
    }

    private func refresh() {
        fit = AlignmentSolver.fit(pairs: pairs, zone: zone, lockScale: lockScale)
        suggestion = pairs.isEmpty ? nil : ZoneAdvisor.suggest(pairs: pairs.map {
            (drawingX: $0.drawingX, drawingY: $0.drawingY, latitude: $0.latitudeDegrees, longitude: $0.longitudeDegrees)
        })
        refreshWarning()
        refreshMap()
    }

    private func refreshWarning() {
        guard activeTransform == nil, let document, let reference, !document.bounds.isEmpty else {
            warning = nil
            return
        }
        warning = ZoneAdvisor.placement(
            drawingX: document.bounds.midX,
            drawingY: document.bounds.midY,
            zone: zone,
            axis: axis,
            referenceLatitude: reference.latitude,
            referenceLongitude: reference.longitude,
            referenceName: reference.name
        )
    }

    private func refreshMap() {
        guard let document else {
            mapPaths = []
            overlayCapped = false
            mapRevision += 1
            return
        }
        let built = DrawingPlacement.overlay(
            document: document,
            zone: zone,
            axis: axis,
            transform: activeTransform,
            composesAxis: activeComposesAxis
        )
        mapPaths = built.paths
        overlayCapped = built.capped
        mapRevision += 1
    }
}
