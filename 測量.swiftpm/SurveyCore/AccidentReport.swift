import Foundation

/// 対外説明で氏名を出すか、関係者番号に置き換えるか。
public enum AccidentNames: String, Equatable, Sendable {
    case shown
    case anonymous

    public var label: String {
        switch self {
        case .shown: return "氏名あり"
        case .anonymous: return "匿名"
        }
    }
}

/// 確定した記録のあとに足す一行。記録.json は変えない。
public struct AccidentNote: Codable, Equatable, Sendable {
    public var at: Date
    public var previous: String
    public var text: String
    public var hash: String

    public init(at: Date, previous: String, text: String, hash: String) {
        self.at = at
        self.previous = previous
        self.text = text
        self.hash = hash
    }
}

public struct AccidentIntegrity: Equatable, Sendable {
    public var recordHash: String
    public var storedHash: String?
    public var recordStatus: String
    public var appendixStatus: String
    public var tipHash: String?

    public init(recordHash: String, storedHash: String?, recordStatus: String, appendixStatus: String, tipHash: String?) {
        self.recordHash = recordHash
        self.storedHash = storedHash
        self.recordStatus = recordStatus
        self.appendixStatus = appendixStatus
        self.tipHash = tipHash
    }
}

public struct AccidentDocument: Equatable, Sendable {
    public var narrative: [String]
    public var summary: [String]
    public var integrity: AccidentIntegrity
    public var snapshotPNG: Data

    public init(narrative: [String], summary: [String], integrity: AccidentIntegrity, snapshotPNG: Data) {
        self.narrative = narrative
        self.summary = summary
        self.integrity = integrity
        self.snapshotPNG = snapshotPNG
    }
}

public struct AccidentExport: Equatable, Sendable {
    public var fileName: String
    public var status: String
    public var hash: String

    public init(fileName: String, status: String, hash: String) {
        self.fileName = fileName
        self.status = status
        self.hash = hash
    }
}

public enum AccidentReport {
    public static let title = "対外説明"
    public static let formNote = "このページは労働者死傷病報告へ転記するための抜粋です。様式そのものは作らず、提出もしません。"
    public static let missingFields = "未記録 性別、年齢、職種、経験期間、傷病名、傷病部位、休業日数、事故の型、起因物"

    public static func clock(_ date: Date) -> String {
        stamp.string(from: date)
    }

    public static func priorTrack(_ record: IncidentRecord) -> [IncidentSample] {
        record.track.filter { sample in
            let delta = sample.at.timeIntervalSince(record.occurredAt)
            return delta >= -IncidentBook.beforeSeconds && delta <= 0
        }.sorted { $0.at < $1.at }
    }

    public static func document(
        _ record: IncidentRecord,
        notes: [AccidentNote],
        names: AccidentNames,
        integrity: AccidentIntegrity,
        generatedAt: Date
    ) -> AccidentDocument {
        let masked = mask(record, notes: notes, names: names)
        let narrative = narrativeLines(
            record: masked.record,
            notes: masked.notes,
            names: names,
            integrity: integrity,
            generatedAt: generatedAt
        )
        let summary = summaryLines(record: masked.record, notes: masked.notes)
        let origin = masked.record.parties.first
        let snapshot = IncidentPNG.drawing(
            parties: masked.record.parties,
            track: priorTrack(masked.record),
            radiusMeters: masked.record.machineRadiusMeters,
            strokes: [],
            originLatitude: origin?.latitudeDegrees ?? 0,
            originLongitude: origin?.longitudeDegrees ?? 0
        )
        return AccidentDocument(narrative: narrative, summary: summary, integrity: integrity, snapshotPNG: snapshot)
    }

    public static func pdf(_ document: AccidentDocument) -> Data {
        let image = IncidentPNG.rgb(document.snapshotPNG).map { ($0.width, $0.height, $0.rgb) }
        return IncidentPDF.illustrated(sections: [document.narrative, document.summary], image: image)
    }

    static func narrativeLines(
        record: IncidentRecord,
        notes: [AccidentNote],
        names: AccidentNames,
        integrity: AccidentIntegrity,
        generatedAt: Date
    ) -> [String] {
        var lines = [
            title,
            "この文書は確定したインシデント記録から作っています。記録.json は書き換えていません。",
            "生成時刻 \(clock(generatedAt))",
            "記録のSHA-256 \(integrity.recordHash)",
            "照合 \(integrity.recordStatus)",
            "追記 \(integrity.appendixStatus)",
            "照合は、確定時に書いたハッシュと記録.json を比べています。"
        ]
        if let tip = integrity.tipHash {
            lines.append("追記の先端 \(tip)")
        }
        lines.append(names == .anonymous ? "氏名 匿名" : "氏名 表示")
        if names == .anonymous {
            lines.append("個人名は関係者1から順に置き換えています。対応表はこの文書に残しません。")
        }
        lines.append("時系列")
        lines.append(contentsOf: timeline(record, notes: notes))
        lines.append("発生場所")
        if let party = record.parties.first {
            lines.append("緯度 \(coordinate(party.latitudeDegrees))")
            lines.append("経度 \(coordinate(party.longitudeDegrees))")
        } else {
            lines.append("座標 未記録")
        }
        lines.append("住所 \(filled(record.address))")
        lines.append("図面")
        lines.append("赤は重機、黄は人、灰は直前60秒の軌跡、橙の円は作業半径です。")
        let track = priorTrack(record)
        lines.append("直前60秒の軌跡 \(track.count)点")
        for sample in track.prefix(8) {
            lines.append("\(clock(sample.at)) \(sample.name) \(coordinate(sample.latitudeDegrees)) \(coordinate(sample.longitudeDegrees))")
        }
        if track.count > 8 {
            lines.append("残りの軌跡は図にあります。")
        }
        lines.append("位置")
        if record.parties.isEmpty {
            lines.append("未記録")
        } else {
            for party in record.parties {
                let radius = party.workRadiusMeters.map { " 作業半径 \(tenths($0))m" } ?? ""
                lines.append("\(party.name)（\(party.role.label)） \(coordinate(party.latitudeDegrees)) \(coordinate(party.longitudeDegrees))\(radius)")
            }
        }
        lines.append("作業 \(record.work.kind) \(record.work.name)")
        lines.append("作業半径 \(tenths(record.machineRadiusMeters))m")
        lines.append("天候 \(filled(record.weather))")
        lines.append("無線")
        if record.radio.isEmpty {
            lines.append("音声なし")
        } else {
            for clip in record.radio {
                let heard = clip.audioByteCount > 0 || clip.audioFile != nil
                let end = clip.endedAt.map { "から \(clock($0))" } ?? "開始のみ"
                lines.append("\(heard ? "音声あり" : "音声なし") \(clock(clip.startedAt)) \(end) \(clip.speaker)")
            }
        }
        return lines
    }

    static func summaryLines(record: IncidentRecord, notes: [AccidentNote]) -> [String] {
        let place: String
        if let party = record.parties.first {
            place = "緯度 \(coordinate(party.latitudeDegrees)) 経度 \(coordinate(party.longitudeDegrees)) 住所 \(filled(record.address))"
        } else {
            place = "座標 未記録 住所 \(filled(record.address))"
        }
        let people = record.parties.map { "\($0.name)（\($0.role.label)）" }.joined(separator: "、")
        let outline = timeline(record, notes: notes)
            .filter { !$0.hasSuffix("未記録") }
            .joined(separator: "。")
        return [
            "労働者死傷病報告に使う項目",
            formNote,
            "事業場の名称 \(record.projectName)",
            "事業場の所在地 \(filled(record.address))",
            "災害発生日時 \(clock(record.occurredAt))",
            "災害発生場所 \(place)",
            "関係者 \(people.isEmpty ? "未記録" : people)",
            "被災者の氏名 特定していません",
            "作業内容 \(record.work.kind) \(record.work.name)",
            "作業半径 \(tenths(record.machineRadiusMeters))m",
            "天候 \(filled(record.weather))",
            "災害の概況 \(outline.isEmpty ? "未記録" : outline)",
            missingFields
        ]
    }

    static func timeline(_ record: IncidentRecord, notes: [AccidentNote]) -> [String] {
        let dated: [(Date, String)] = [
            (record.occurredAt, "発生 \(clock(record.occurredAt))"),
            (record.occurredAt, "検知 \(record.trigger.label) \(clock(record.occurredAt))")
        ]
        var alarm: [(Date, String)] = []
        if record.trigger == .alarm {
            alarm.append((record.occurredAt, "警報 \(clock(record.occurredAt)) \(record.trigger.label)"))
        }
        for speech in record.speeches where speech.text.contains("警報") {
            alarm.append((speech.at, "警報 \(clock(speech.at)) \(speech.text)"))
        }
        var response: [(Date, String)] = []
        var reported: [(Date, String)] = []
        var arrived: [(Date, String)] = []
        for stamp in record.aidLog ?? [] {
            if stamp.text.contains("担当確定") || stamp.text.contains("迎え確定") || stamp.text.contains("向かって") {
                response.append((stamp.at, "駆けつけ \(clock(stamp.at)) \(stamp.text)"))
            }
            if stamp.text.contains("119") {
                reported.append((stamp.at, "通報 \(clock(stamp.at)) \(stamp.text)"))
            }
            if stamp.text.hasPrefix("救急到着") {
                arrived.append((stamp.at, "救急到着 \(clock(stamp.at))"))
            }
        }
        for speech in record.speeches where speech.text.contains("向かって") {
            response.append((speech.at, "駆けつけ \(clock(speech.at)) \(speech.text)"))
        }
        for note in notes where note.text.hasPrefix("救急到着") {
            arrived.append((note.at, "救急到着 \(clock(note.at))"))
        }
        var lines: [String] = []
        lines.append(contentsOf: dated.sorted { $0.0 < $1.0 }.map(\.1))
        lines.append(contentsOf: ordered(alarm, empty: "警報 未記録"))
        lines.append(contentsOf: ordered(response, empty: "駆けつけ 未記録"))
        lines.append(contentsOf: ordered(reported, empty: "通報 未記録"))
        lines.append(contentsOf: ordered(arrived, empty: "救急到着 未記録"))
        return lines
    }

    private static func ordered(_ rows: [(Date, String)], empty: String) -> [String] {
        let unique = rows.sorted { $0.0 < $1.0 }.map(\.1)
        var seen: [String] = []
        for line in unique where !seen.contains(line) {
            seen.append(line)
        }
        return seen.isEmpty ? [empty] : seen
    }

    private static func mask(
        _ record: IncidentRecord,
        notes: [AccidentNote],
        names: AccidentNames
    ) -> (record: IncidentRecord, notes: [AccidentNote]) {
        guard names == .anonymous else { return (record, notes) }
        var order: [String] = []
        func collect(_ name: String) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !order.contains(trimmed) else { return }
            order.append(trimmed)
        }
        for party in record.parties { collect(party.name) }
        for sample in record.track.sorted(by: { $0.at < $1.at }) { collect(sample.name) }
        for clip in record.radio { collect(clip.speaker) }
        let labels = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, "関係者\($0.offset + 1)") })
        func rewrite(_ text: String) -> String {
            var result = text
            for name in order.sorted(by: { $0.count > $1.count }) {
                guard let label = labels[name] else { continue }
                result = result.replacingOccurrences(of: name, with: label)
            }
            return result
        }
        var copy = record
        copy.parties = record.parties.map { party in
            var next = party
            next.name = rewrite(party.name)
            return next
        }
        copy.track = record.track.map { sample in
            var next = sample
            next.name = rewrite(sample.name)
            return next
        }
        copy.speeches = record.speeches.map { speech in
            IncidentSpeech(at: speech.at, text: rewrite(speech.text))
        }
        copy.radio = record.radio.map { clip in
            var next = clip
            next.speaker = rewrite(clip.speaker)
            return next
        }
        copy.aidLog = record.aidLog?.map { stamp in
            AidStamp(at: stamp.at, text: rewrite(stamp.text))
        }
        let hidden = notes.map { note in
            AccidentNote(at: note.at, previous: note.previous, text: rewrite(note.text), hash: note.hash)
        }
        return (copy, hidden)
    }

    private static func filled(_ text: String?) -> String {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "未記録" : trimmed
    }

    private static func coordinate(_ degrees: Double) -> String {
        String(format: "%.8f", degrees)
    }

    private static func tenths(_ meters: Double) -> String {
        String(format: "%.1f", MachineReach.roundTenths(meters))
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

public enum AccidentBook {
    public static func judge(recordBytes: Data, storedHash: String?, notes: [AccidentNote]) -> AccidentIntegrity {
        let hash = SHA256.hex(recordBytes)
        let stored = storedHash?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordStatus: String
        if let stored, !stored.isEmpty {
            recordStatus = stored == hash ? "一致" : "不一致"
        } else {
            recordStatus = "照合用ハッシュが無い"
        }
        let anchor = (stored?.isEmpty == false ? stored : nil) ?? hash
        var expected = anchor
        var broken = false
        for note in notes {
            let again = digest(previous: note.previous, at: note.at, text: note.text)
            if note.previous != expected || note.hash != again {
                broken = true
            }
            expected = note.hash
        }
        let appendix = notes.isEmpty ? "追記なし" : (broken ? "切れている" : "つながっている")
        return AccidentIntegrity(
            recordHash: hash,
            storedHash: stored?.isEmpty == false ? stored : nil,
            recordStatus: recordStatus,
            appendixStatus: appendix,
            tipHash: notes.last?.hash
        )
    }

    public static func append(
        text: String,
        at date: Date,
        incidentID: UUID,
        projectName: String,
        root: URL
    ) throws -> AccidentNote {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { throw IncidentError.missingOpening }
        let directory = try IncidentBook.directory(incidentID: incidentID, projectName: projectName, at: root)
        let recordURL = directory.appendingPathComponent(IncidentBook.recordName)
        guard let recordBytes = try? Data(contentsOf: recordURL) else { throw IncidentError.missingOpening }
        let stored = storedHash(in: directory)
        let notes = loadNotes(in: directory)
        let previous = notes.last?.hash ?? stored ?? SHA256.hex(recordBytes)
        let whole = Date(timeIntervalSince1970: TimeInterval(Int(date.timeIntervalSince1970)))
        let note = AccidentNote(at: whole, previous: previous, text: trimmed, hash: digest(previous: previous, at: whole, text: trimmed))
        let url = directory.appendingPathComponent(IncidentBook.noteName)
        var line = try json(note)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
        return note
    }

    @discardableResult
    public static func export(
        incidentID: UUID,
        projectName: String,
        at root: URL,
        names: AccidentNames,
        generatedAt: Date
    ) throws -> AccidentExport {
        let directory = try IncidentBook.directory(incidentID: incidentID, projectName: projectName, at: root)
        let recordURL = directory.appendingPathComponent(IncidentBook.recordName)
        let recordBytes = try Data(contentsOf: recordURL)
        let record = try JSONDecoder.incident.decode(IncidentRecord.self, from: recordBytes)
        let notes = loadNotes(in: directory)
        let integrity = judge(recordBytes: recordBytes, storedHash: storedHash(in: directory), notes: notes)
        let document = AccidentReport.document(record, notes: notes, names: names, integrity: integrity, generatedAt: generatedAt)
        let folder = directory.appendingPathComponent(IncidentBook.explanationDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = fileStamp.string(from: generatedAt)
        var url = folder.appendingPathComponent("\(stamp)-\(names.label).pdf")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stamp)-\(names.label)-\(suffix).pdf")
            suffix += 1
        }
        try AccidentReport.pdf(document).write(to: url)
        return AccidentExport(fileName: url.lastPathComponent, status: integrity.recordStatus, hash: integrity.recordHash)
    }

    static func digest(previous: String, at date: Date, text: String) -> String {
        let body = AccidentBody(at: date, previous: previous, text: text)
        let data = (try? json(body)) ?? Data()
        return SHA256.hex(data)
    }

    static func loadNotes(in directory: URL) -> [AccidentNote] {
        let url = directory.appendingPathComponent(IncidentBook.noteName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder.incident.decode(AccidentNote.self, from: data)
        }
    }

    private static func storedHash(in directory: URL) -> String? {
        let url = directory.appendingPathComponent(IncidentBook.hashName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct AccidentBody: Encodable {
    var at: Date
    var previous: String
    var text: String
}

extension JSONDecoder {
    static var incident: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
