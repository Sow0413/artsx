import Foundation

/// 一覧に出す点の絞り込み。水準器の点は測量の組に入れない。
public struct SurveyPointGroup: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var rows: [FieldObservation]

    public init(id: String, title: String, rows: [FieldObservation]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

public enum SurveyList {
    public static let levelOrigin = "level"
    /// 座標簿に残る簡易ターゲット。古い記録は origin が無いので、この種別でも除く。
    public static let levelKind = "簡易ターゲット"

    public static let surveyGroups: [(id: String, title: String)] = [
        ("preview", "下見"),
        ("rough", "概略"),
        ("traverse", "測量"),
        ("boundary", "境界")
    ]

    public static let buildGroups: [(id: String, title: String)] = [
        ("stakeout", "丁張"),
        ("asBuilt", "出来形")
    ]

    public static func isLevel(_ observation: FieldObservation, bookKind: String?) -> Bool {
        if observation.origin == levelOrigin { return true }
        // 古い簡易ターゲットは origin が無い。座標簿の種別だけで除く。
        return observation.origin == nil && bookKind == levelKind
    }

    public static func matchesProject(_ observation: FieldObservation, projectID: String?) -> Bool {
        guard let projectID else { return true }
        return observation.projectID == nil || observation.projectID == projectID
    }

    /// 同じ点名は新しい観測だけ。水準と、別の現場の点は除く。
    public static func grouped(
        _ observations: [FieldObservation],
        groups: [(id: String, title: String)],
        bookKinds: [String: String],
        projectID: String?
    ) -> [SurveyPointGroup] {
        groups.compactMap { group in
            let rows = latest(observations.filter { item in
                item.workID == group.id
                    && matchesProject(item, projectID: projectID)
                    && !isLevel(item, bookKind: bookKinds[item.name])
            })
            if rows.isEmpty { return nil }
            return SurveyPointGroup(id: group.id, title: group.title, rows: rows)
        }
    }

    public static func latest(_ observations: [FieldObservation]) -> [FieldObservation] {
        var byName: [String: FieldObservation] = [:]
        for item in observations {
            if let current = byName[item.name], current.captured.timestamp > item.captured.timestamp {
                continue
            }
            byName[item.name] = item
        }
        return byName.values.sorted { lhs, rhs in
            if lhs.captured.timestamp != rhs.captured.timestamp {
                return lhs.captured.timestamp > rhs.captured.timestamp
            }
            return lhs.name < rhs.name
        }
    }
}

/// ゴミ箱に 30 日残す1件。すぐには消さない。
public struct PointTrashPayload: Codable, Equatable, Sendable {
    public var observations: [FieldObservation]
    public var book: CoordinateBookEntry?
    public var records: [String]
    public var drawingProject: String?
    public var drawingPoint: FieldPoint?

    public init(
        observations: [FieldObservation] = [],
        book: CoordinateBookEntry? = nil,
        records: [String] = [],
        drawingProject: String? = nil,
        drawingPoint: FieldPoint? = nil
    ) {
        self.observations = observations
        self.book = book
        self.records = records
        self.drawingProject = drawingProject
        self.drawingPoint = drawingPoint
    }
}

public struct TrashedPoint: Identifiable, Equatable, Sendable {
    public static let retention: TimeInterval = 30 * 24 * 60 * 60

    public var id: UUID
    public var name: String
    public var deletedAt: Date
    public var payload: PointTrashPayload

    public init(id: UUID = UUID(), name: String, deletedAt: Date, payload: PointTrashPayload) {
        self.id = id
        self.name = name
        self.deletedAt = deletedAt
        self.payload = payload
    }

    public func isExpired(at now: Date) -> Bool {
        now.timeIntervalSince(deletedAt) >= Self.retention
    }

    public func daysLeft(at now: Date) -> Int {
        let remaining = Self.retention - now.timeIntervalSince(deletedAt)
        if remaining <= 0 { return 0 }
        return Int(ceil(remaining / (24 * 60 * 60)))
    }
}

public struct ArchivedBookEntry: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var replacedAt: Date
    public var entry: CoordinateBookEntry

    public init(id: UUID, name: String, replacedAt: Date, entry: CoordinateBookEntry) {
        self.id = id
        self.name = name
        self.replacedAt = replacedAt
        self.entry = entry
    }
}
