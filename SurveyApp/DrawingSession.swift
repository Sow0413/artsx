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
    @Published private(set) var backgroundVerdict: BackgroundVerdict?
    @Published private(set) var backgroundBusy = false
    @Published private(set) var activeRecordFolder: String?

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
        refresh()
    }

    func importFile(data: Data, fileName rawName: String) {
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
            refresh()
        } catch let error as DXFError {
            message = error.description
        } catch let error as SFCError {
            message = error.description
        } catch {
            message = "図面を読めませんでした。"
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

    func setRole(_ role: DrawingLayerRole, visible: Bool) {
        document = document?.settingRole(role, visible: visible)
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
