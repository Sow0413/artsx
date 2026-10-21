import Foundation

public struct CoordinateBookQuery: Sendable, Equatable {
    public var namePrefix: String
    public var kind: String
    public var source: String
    public var minimumStage: PositionStage?
    public var maximumHorizontalMeters: Double?
    /// 取込日。`yyyy-MM-dd`。日本時間。
    public var importedDay: String?
    public var bounds: GeoBounds?

    public init(
        namePrefix: String = "",
        kind: String = "",
        source: String = "",
        minimumStage: PositionStage? = nil,
        maximumHorizontalMeters: Double? = nil,
        importedDay: String? = nil,
        bounds: GeoBounds? = nil
    ) {
        self.namePrefix = namePrefix
        self.kind = kind
        self.source = source
        self.minimumStage = minimumStage
        self.maximumHorizontalMeters = maximumHorizontalMeters
        self.importedDay = importedDay
        self.bounds = bounds
    }

    public func matches(_ entry: CoordinateBookEntry) -> Bool {
        let prefix = namePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefix.isEmpty, !entry.name.uppercased().hasPrefix(prefix.uppercased()) { return false }
        let wantedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        if !wantedKind.isEmpty, entry.kind != wantedKind { return false }
        let wantedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !wantedSource.isEmpty, entry.source != wantedSource { return false }
        if let minimumStage {
            guard let stage = entry.stage, stage.rawValue >= minimumStage.rawValue else { return false }
        }
        if let maximumHorizontalMeters {
            guard entry.source != "既知点" else { return false }
            guard entry.horizontalAccuracyMeters <= maximumHorizontalMeters else { return false }
        }
        if let importedDay, !importedDay.isEmpty {
            guard Self.day(of: entry.recordedAt) == importedDay else { return false }
        }
        if let bounds, !bounds.contains(latitude: entry.latitudeDegrees, longitude: entry.longitudeDegrees) {
            return false
        }
        return true
    }

    public static func apply(_ entries: [CoordinateBookEntry], query: CoordinateBookQuery) -> [CoordinateBookEntry] {
        entries.filter { query.matches($0) }.sorted { $0.name < $1.name }
    }

    static func day(of date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

public enum CoordinateBookIndex {
    public static func collect(
        book: [CoordinateBookEntry],
        observations: [FieldObservation],
        known: [ControlPoint]
    ) -> [CoordinateBookEntry] {
        var byName: [String: CoordinateBookEntry] = [:]
        for point in known {
            byName[point.name] = CoordinateBookEntry(
                name: point.name,
                latitudeDegrees: point.latitudeDegrees,
                longitudeDegrees: point.longitudeDegrees,
                ellipsoidalHeightMeters: point.comparableEllipsoidalHeightMeters ?? point.heightMeters,
                horizontalAccuracyMeters: 0,
                verticalAccuracyMeters: nil,
                satelliteCount: nil,
                fixDurationSeconds: 0,
                recordedAt: Date(timeIntervalSince1970: 0),
                kind: point.kind,
                source: "既知点",
                stage: nil,
                solution: nil
            )
        }
        for observation in observations {
            byName[observation.name] = entry(from: observation)
        }
        for saved in book {
            byName[saved.name] = saved
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    public static func entry(from observation: FieldObservation, kind: String? = nil, source: String = "観測") -> CoordinateBookEntry {
        let condition = observation.condition
        let ellipsoidal = condition?.surveyEllipsoidalMeters ?? condition?.stature?.groundHeightMeters ?? observation.captured.ellipsoidalHeightMeters
        let resolved = SurveyHeight.resolve(
            ellipsoidalMeters: ellipsoidal,
            latitudeDegrees: observation.captured.latitudeDegrees,
            longitudeDegrees: observation.captured.longitudeDegrees,
            meanSeaLevelMeters: observation.captured.meanSeaLevelMeters,
            deviceEllipsoidalMeters: observation.captured.ellipsoidalHeightMeters
        )
        return CoordinateBookEntry(
            name: observation.name,
            latitudeDegrees: observation.captured.latitudeDegrees,
            longitudeDegrees: observation.captured.longitudeDegrees,
            ellipsoidalHeightMeters: ellipsoidal,
            horizontalAccuracyMeters: observation.horizontalAccuracyAtCapture,
            verticalAccuracyMeters: observation.verticalAccuracyAtCapture,
            satelliteCount: condition?.satelliteCount ?? observation.captured.satelliteCount,
            fixDurationSeconds: observation.fixDurationSeconds ?? condition?.durationSeconds ?? 0,
            recordedAt: observation.captured.timestamp,
            kind: kind ?? (observation.workID == "boundary" ? "基準点" : observation.workID),
            source: source,
            stage: condition?.stage ?? observation.captured.stage,
            solution: condition?.solution ?? observation.captured.fixQuality,
            pdop: condition?.pdop ?? observation.captured.pdop,
            correctionAgeSeconds: condition?.correctionAgeSeconds ?? observation.captured.correctionAgeSeconds,
            correctionSource: condition?.correctionSource ?? observation.captured.correctionSource,
            epochCount: condition?.epochCount,
            receiverLabel: (condition?.receiver ?? observation.captured.receiver).label,
            satelliteNote: condition?.satelliteNote,
            orthometricHeightMeters: condition?.orthometricHeightMeters ?? resolved.orthometricMeters,
            geoidUndulationMeters: condition?.geoidUndulationMeters ?? resolved.geoidMeters,
            geoidModel: condition?.geoidModel ?? resolved.model
        )
    }
}

public enum DeliveryFormat: String, CaseIterable, Sendable, Identifiable {
    case sima
    case csv
    case dxf
    case sfc
    case asBuiltPDF

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sima: return "SIMA"
        case .csv: return "座標一覧"
        case .dxf: return "DXF"
        case .sfc: return "SFC"
        case .asBuiltPDF: return "出来形管理表PDF"
        }
    }

    public var filename: String {
        switch self {
        case .sima: return "座標.sima"
        case .csv: return "座標一覧.csv"
        case .dxf: return "座標.dxf"
        case .sfc: return "座標.sfc"
        case .asBuiltPDF: return "出来形管理表.pdf"
        }
    }
}

public enum CoordinateDelivery {
    public static let pointCloudNote = "点群と3Dは点群フォルダに保存するだけです。受取手への既定の出力には入れません。"

    public static func data(_ entries: [CoordinateBookEntry], format: DeliveryFormat, zone: Int) -> Data {
        switch format {
        case .sima: return Data(sima(entries, zone: zone).utf8)
        case .csv: return Data(csv(entries, zone: zone).utf8)
        case .dxf: return Data(dxf(entries, zone: zone).utf8)
        case .sfc: return Data(sfc(entries, zone: zone).utf8)
        case .asBuiltPDF: return pdf(entries, zone: zone)
        }
    }

    public static func sima(_ entries: [CoordinateBookEntry], zone: Int) -> String {
        var lines = ["G00,02,"]
        for (index, entry) in entries.enumerated() {
            let plane = projected(entry, zone: zone)
            let height = entry.deliveredHeightMeters.map { String(format: "%.3f", $0) } ?? ""
            lines.append("A01,\(index + 1),\(entry.name),\(number(plane?.northing)),\(number(plane?.easting)),\(height),")
        }
        lines.append("A99,")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func csv(_ entries: [CoordinateBookEntry], zone: Int) -> String {
        var lines = ["点名,種類,出典,解,段階,北,東,緯度,経度,標高,水平精度m,高さ精度m,PDOP,衛星,補正遅れ秒,補正元,観測時刻,秒数,エポック,機器,楕円体高,ジオイドm,ジオイド"]
        for entry in entries {
            lines.append(csvRow(entry, zone: zone))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func dxf(_ entries: [CoordinateBookEntry], zone: Int) -> String {
        var body = """
        0
        SECTION
        2
        HEADER
        9
        $DWGCODEPAGE
        3
        UTF-8
        9
        $INSUNITS
        70
        6
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES

        """
        for entry in entries {
            guard let plane = projected(entry, zone: zone) else { continue }
            let height = entry.deliveredHeightMeters ?? 0
            body += """
            0
            POINT
            8
            座標
            10
            \(String(format: "%.3f", plane.easting))
            20
            \(String(format: "%.3f", plane.northing))
            30
            \(String(format: "%.3f", height))
            0
            TEXT
            8
            座標
            10
            \(String(format: "%.3f", plane.easting))
            20
            \(String(format: "%.3f", plane.northing))
            40
            1.0
            1
            \(entry.name)

            """
        }
        body += """
        0
        ENDSEC
        0
        EOF

        """
        return body
    }

    public static func sfc(_ entries: [CoordinateBookEntry], zone: Int) -> String {
        var features = ["#1=layer_feature('座標','1');"]
        var number = 2
        for entry in entries {
            guard let plane = projected(entry, zone: zone) else { continue }
            features.append("#\(number)=point_feature(1,2,1,1,\(String(format: "%.3f", plane.easting)),\(String(format: "%.3f", plane.northing)));")
            number += 1
            features.append("#\(number)=text_string_feature(1,1,1,'\(entry.name)',\(String(format: "%.3f", plane.easting)),\(String(format: "%.3f", plane.northing)),1.5,1,0);")
            number += 1
        }
        return """
        ISO-10303-21;
        HEADER;
        FILE_NAME('座標.sfc','',(''),(''),'SCADEC_API_Ver3.0$$3.0','','');
        ENDSEC;
        DATA;
        /*SXF
        \(features.joined(separator: "\n"))
        SXF*/
        ENDSEC;
        END-ISO-10303-21;

        """
    }

    public static func sheet(_ entries: [CoordinateBookEntry], zone: Int) -> String {
        var lines = [
            "出来形管理表",
            "設計値は未入力です。測定値と観測状況だけ出しています。",
            "点群と3Dはこの表に入れません。"
        ]
        if entries.isEmpty {
            lines.append("出力する点がありません。")
            return lines.joined(separator: "\n")
        }
        for entry in entries {
            let plane = projected(entry, zone: zone)
            lines.append("")
            lines.append(entry.name)
            lines.append("種類 \(entry.kind ?? "—")　出典 \(entry.source ?? "—")")
            if let plane {
                lines.append(String(format: "北 %.3f m　東 %.3f m", plane.northing, plane.easting))
            }
            if let condition = condition(from: entry) {
                lines.append(contentsOf: condition.reportLines)
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func pdf(_ entries: [CoordinateBookEntry], zone: Int) -> Data {
        var lines = ["As-built", "design value is not entered"]
        for entry in entries {
            let plane = projected(entry, zone: zone)
            let north = number(plane?.northing)
            let east = number(plane?.easting)
            let solution = entry.solution.map { FixQualityLabel.of($0, receiver: entry.receiverLabel) } ?? "-"
            lines.append("\(entry.name) N \(north) E \(east) H \(entry.horizontalAccuracyMeters) \(solution)")
        }
        lines.append("")
        lines.append(contentsOf: sheet(entries, zone: zone).components(separatedBy: "\n"))
        return PDFText.document(lines: lines)
    }

    private static func condition(from entry: CoordinateBookEntry) -> ObservationCondition? {
        guard let solution = entry.solution, let stage = entry.stage else { return nil }
        let receiver = ReceiverKind.allCases.first { $0.label == entry.receiverLabel } ?? .rtk
        return ObservationCondition(
            solution: solution,
            solutionLabel: FixQualityLabel.of(solution, receiver: entry.receiverLabel),
            satellites: [],
            satelliteCount: entry.satelliteCount,
            pdop: entry.pdop,
            horizontalAccuracyMeters: entry.horizontalAccuracyMeters,
            verticalAccuracyMeters: entry.verticalAccuracyMeters,
            correctionAgeSeconds: entry.correctionAgeSeconds,
            correctionSource: entry.correctionSource,
            observedAt: entry.recordedAt,
            durationSeconds: entry.fixDurationSeconds,
            epochCount: entry.epochCount,
            receiver: receiver,
            stage: stage,
            surveyEllipsoidalMeters: entry.ellipsoidalHeightMeters,
            orthometricHeightMeters: entry.orthometricHeightMeters,
            geoidUndulationMeters: entry.geoidUndulationMeters,
            geoidModel: entry.geoidModel
        )
    }

    private static func csvRow(_ entry: CoordinateBookEntry, zone: Int) -> String {
        let plane = projected(entry, zone: zone)
        let solution = entry.solution.map { FixQualityLabel.of($0, receiver: entry.receiverLabel) } ?? ""
        let stage = entry.stage.map { "\($0.rawValue)" } ?? ""
        let height = entry.deliveredHeightMeters.map { String(format: "%.3f", $0) } ?? ""
        let ellipsoidal = entry.ellipsoidalHeightMeters.map { String(format: "%.3f", $0) } ?? ""
        let geoid = entry.geoidUndulationMeters.map { String(format: "%.3f", $0) } ?? ""
        let vertical = entry.verticalAccuracyMeters.map { String(format: "%.3f", $0) } ?? ""
        let pdop = entry.pdop.map { String(format: "%.2f", $0) } ?? ""
        let satellites = entry.satelliteNote ?? entry.satelliteCount.map { "\($0)" } ?? ""
        let age = entry.correctionAgeSeconds.map { String(format: "%.1f", $0) } ?? ""
        let epochs = entry.epochCount.map { "\($0)" } ?? ""
        let columns = [
            entry.name,
            entry.kind ?? "",
            entry.source ?? "",
            solution,
            stage,
            number(plane?.northing),
            number(plane?.easting),
            String(format: "%.8f", entry.latitudeDegrees),
            String(format: "%.8f", entry.longitudeDegrees),
            height,
            String(format: "%.3f", entry.horizontalAccuracyMeters),
            vertical,
            pdop,
            satellites,
            age,
            entry.correctionSource ?? "",
            ObservationCondition.stamp.string(from: entry.recordedAt),
            String(format: "%.0f", entry.fixDurationSeconds),
            epochs,
            entry.receiverLabel ?? "",
            ellipsoidal,
            geoid,
            entry.geoidModel ?? ""
        ]
        return columns.joined(separator: ",")
    }

    private static func projected(_ entry: CoordinateBookEntry, zone: Int) -> (northing: Double, easting: Double)? {
        guard let plane = PlaneRectangular.forward(
            latitudeDegrees: entry.latitudeDegrees,
            longitudeDegrees: entry.longitudeDegrees,
            zone: zone
        ) else { return nil }
        return (plane.northingMeters, plane.eastingMeters)
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.3f", value)
    }
}

enum FixQualityLabel {
    static func of(_ quality: FixQuality, receiver: String?) -> String {
        if receiver == ReceiverKind.iphoneGPS.label { return "単独" }
        switch quality {
        case .rtkFix: return receiver == ReceiverKind.clas.label ? "CLAS" : "FIX"
        case .float: return "FLOAT"
        case .clas: return "CLAS"
        case .dgps: return "DGPS"
        case .standalone, .none: return "単独"
        }
    }
}

enum PDFText {
    static func document(lines: [String]) -> Data {
        let ascii = lines.filter { $0.utf8.allSatisfy { $0 < 128 } }
        let japanese = lines.filter { !$0.utf8.allSatisfy { $0 < 128 } }
        var commands = "BT\n/F1 11 Tf\n40 800 Td\n"
        for line in ascii.prefix(28) {
            commands += "(\(escaped(line))) Tj\n0 -14 Td\n"
        }
        commands += "ET\n"
        if !japanese.isEmpty {
            commands += "BT\n/F2 10 Tf\n40 420 Td\n"
            for line in japanese.prefix(24) {
                commands += "<\(utf16(line))> Tj\n0 -14 Td\n"
            }
            commands += "ET\n"
        }
        let stream = Data(commands.utf8)
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>",
            "<< /Length \(stream.count) >>\nstream\n\(commands)endstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Font /Subtype /Type0 /BaseFont /HeiseiKakuGo-W5 /Encoding /UniJIS-UTF16-H /DescendantFonts [7 0 R] >>",
            "<< /Type /Font /Subtype /CIDFontType0 /BaseFont /HeiseiKakuGo-W5 /CIDSystemInfo << /Registry (Adobe) /Ordering (Japan1) /Supplement 2 >> >>"
        ]
        var body = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(body.count)
            body.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let xref = body.count
        var table = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() {
            table += String(format: "%010d 00000 n \n", offset)
        }
        body.append(Data(table.utf8))
        body.append(Data("trailer << /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return body
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    private static func utf16(_ text: String) -> String {
        var hex = "FEFF"
        for unit in text.utf16 {
            hex += String(format: "%04X", unit)
        }
        return hex
    }
}
