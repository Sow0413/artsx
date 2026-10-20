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
        refresh()
    }

    func importFile(data: Data, fileName rawName: String) {
        guard var current = project else {
            message = "先にプロジェクトを作ってください。"
            return
        }
        do {
            let parsed = try DXFParser.parse(data)
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
            var note = "設計に \(stored) を置きました。元の DXF は変えていません。"
            if let unit = parsed.unitWarning { note += unit }
            if !parsed.unsupportedSummary.isEmpty { note += "読めない要素: \(parsed.unsupportedSummary)。" }
            message = note
            refresh()
        } catch let error as DXFError {
            message = error.description
        } catch {
            message = "DXF を読めませんでした。"
        }
    }

    func setZone(_ number: Int) {
        guard PlaneRectangular.zone(number) != nil else { return }
        zone = number
        project?.zone = number
        persistProject()
        refresh()
    }

    func setAxis(_ next: DrawingAxis) {
        axis = next
        project?.axis = next
        persistProject()
        refresh()
    }

    func toggleLayer(_ name: String, visible: Bool) {
        document = document?.settingLayer(name, visible: visible)
        refreshMap()
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
        guard let hit = document.nearestVertex(to: point, tolerance: tolerance) else {
            message = "図面の点の近くをタップしてください。"
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
            fromLongitude: reference?.longitude
        )
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
            message = "先に DXF を読み込んでください。"
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
            message = "合わせ「\(stored.name)」の版 \(stored.version) を設計に置きました。元の DXF は変えていません。"
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

    func addFieldRecord(date: String, kind: String, name: String) {
        guard let project else {
            message = "先にプロジェクトを作ってください。"
            return
        }
        do {
            let note = try ProjectStore.addRecord(
                date: date,
                kind: kind,
                name: name,
                projectName: project.name,
                at: projectsRoot
            )
            message = "記録 \(note.date)_\(note.kind)_\(note.name) を作りました。"
        } catch let error as ProjectStoreError {
            message = error.description
        } catch {
            message = "記録を作れませんでした。"
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
                fromLongitude: longitude
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
        guard let parsed = try? DXFParser.parse(data) else {
            message = "保存してある DXF を読めませんでした。"
            return
        }
        document = parsed
        self.fileName = fileName
        camera.fittedID = nil
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
            transform: activeTransform
        )
        mapPaths = built.paths
        overlayCapped = built.capped
        mapRevision += 1
    }
}
