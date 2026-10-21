import Foundation

/// 画面に出す線の束。Metal でも、まとめて描く Canvas でも、同じ束を渡す。
public struct DrawingBatchStroke: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    /// 画面上の pt。拡大しても変えない。
    public var width: Double
    public var points: [PlanarPoint]

    public init(color: DrawingColor, points: [PlanarPoint], width: Double = DrawingStroke.screenPoints(weight: 1)) {
        red = color.red
        green = color.green
        blue = color.blue
        self.width = width
        self.points = points
    }
}

/// 図面の線は画面の pt で描く。SXF の線幅は相対のヒントで、0.5〜1 pt を超えない。
public enum DrawingStroke {
    public static let minimumPoints = 0.5
    public static let maximumPoints = 1.0
    public static let contour = DrawingColor(red: 0.55, green: 0.57, blue: 0.60)

    /// 1〜8 は SXF の線幅番号。それより大きい値は 0.01 mm とみて、どちらも 0.5〜1 pt に収める。
    public static func screenPoints(weight: Double) -> Double {
        let hint = weight.isFinite && weight > 0 ? weight : 1
        let t: Double
        if hint <= 8 {
            t = (min(8, hint) - 1) / 7
        } else {
            let millimetres = hint / 100
            t = min(1, max(0, (millimetres - 0.13) / (1.0 - 0.13)))
        }
        return minimumPoints + (maximumPoints - minimumPoints) * t
    }

    public static func isContour(_ layer: String) -> Bool {
        let folded = layer.uppercased()
        let markers = ["等高", "計曲線", "主曲線", "補助曲線", "CONTOUR", "CNTR"]
        return markers.contains { folded.contains($0) }
    }

    public static func displayColor(_ color: DrawingColor, layer: String) -> DrawingColor {
        isContour(layer) ? contour : color
    }
}

public struct DrawingBatchPoint: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var point: PlanarPoint

    public init(color: DrawingColor, point: PlanarPoint) {
        red = color.red
        green = color.green
        blue = color.blue
        self.point = point
    }
}

public struct DrawingBatchLabel: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var origin: PlanarPoint
    public var text: String
    public var height: Double

    public init(color: DrawingColor, origin: PlanarPoint, text: String, height: Double) {
        red = color.red
        green = color.green
        blue = color.blue
        self.origin = origin
        self.text = text
        self.height = height
    }
}

public struct DrawingBatch: Sendable, Equatable {
    public var strokes: [DrawingBatchStroke]
    public var points: [DrawingBatchPoint]
    public var labels: [DrawingBatchLabel]

    public init(strokes: [DrawingBatchStroke], points: [DrawingBatchPoint], labels: [DrawingBatchLabel]) {
        self.strokes = strokes
        self.points = points
        self.labels = labels
    }
}

/// 見えている範囲だけ、画面の点の間隔まで間引く。全体が見えるときは升ごとに代表を出す。
public enum DrawingLOD {
    public static let maxStrokes = 2_000
    public static let maxLabels = 40

    public static func batch(document: DrawingDocument, view: DrawingBounds, pointsPerUnit: Double) -> DrawingBatch {
        let visible = Set(document.layers.filter(\.isVisible).map(\.name))
        let pixel = 1 / max(pointsPerUnit, 1e-9)
        let overview = document.entities.count > maxStrokes && coversMost(view, of: document.bounds)
        let ids: [Int]
        if overview {
            let step = max(1, document.entities.count / maxStrokes)
            ids = stride(from: 0, to: document.entities.count, by: step).map { $0 }
        } else {
            ids = document.index.entityIDs(in: view)
        }
        var strokes: [DrawingBatchStroke] = []
        var points: [DrawingBatchPoint] = []
        var labels: [DrawingBatchLabel] = []
        strokes.reserveCapacity(min(ids.count, maxStrokes))
        var contourSeen = 0
        for id in ids {
            if strokes.count >= maxStrokes { break }
            guard document.entities.indices.contains(id) else { continue }
            let entity = document.entities[id]
            guard visible.contains(entity.layer) else { continue }
            if !overview, !entity.bounds.intersects(view) { continue }
            let contour = DrawingStroke.isContour(entity.layer)
            if overview && contour {
                contourSeen += 1
                if contourSeen % 3 != 1 { continue }
            }
            let cull = contour ? pixel * 1.8 : pixel
            if entity.bounds.width < cull, entity.bounds.height < cull, entity.stroke.count > 1 {
                continue
            }
            let limit = overview ? (contour ? 3 : 4) : 48
            let gap = pixel * (overview && contour ? 4 : 1.5)
            let simplified = decimate(entity.stroke, step: gap, limit: limit)
            if simplified.count >= 2 {
                let color = DrawingStroke.displayColor(entity.color, layer: entity.layer)
                let width = DrawingStroke.screenPoints(weight: entity.lineWeight)
                strokes.append(DrawingBatchStroke(color: color, points: simplified, width: width))
            }
            let shown = DrawingStroke.displayColor(entity.color, layer: entity.layer)
            if case let .point(point) = entity.primitive, view.contains(point) || overview {
                points.append(DrawingBatchPoint(color: shown, point: point))
            }
            if labels.count < maxLabels, case let .text(origin, string, height, _) = entity.primitive, height >= pixel * 8 {
                labels.append(DrawingBatchLabel(color: shown, origin: origin, text: string, height: height))
            }
        }
        return DrawingBatch(strokes: strokes, points: points, labels: labels)
    }

    static func coversMost(_ view: DrawingBounds, of bounds: DrawingBounds) -> Bool {
        let span = max(bounds.width, bounds.height, 1)
        return view.width >= span * 0.5 || view.height >= span * 0.5
    }

    static func decimate(_ points: [PlanarPoint], step: Double, limit: Int) -> [PlanarPoint] {
        guard let first = points.first, limit > 0 else { return [] }
        if points.count == 1 { return [first] }
        var kept = [first]
        var last = first
        for point in points.dropFirst() {
            guard kept.count < limit else { break }
            if last.distance(to: point) >= step {
                kept.append(point)
                last = point
            }
        }
        if let end = points.last, kept.count < limit, last.distance(to: end) > 1e-6 {
            kept.append(end)
        }
        return kept
    }
}

public enum DrawingImport {
    /// 解析は呼び出し側のスレッドで行う。画面のスレッドでは呼ばない。
    public static func load(_ data: Data, fileName: String, progress: (WorkProgress) -> Void = { _ in }) throws -> DrawingDocument {
        progress(WorkProgress(label: "図面を読んでいます", fraction: 0.1))
        let ext = (fileName as NSString).pathExtension.lowercased()
        progress(WorkProgress(label: "図面を解析しています", fraction: 0.35))
        let document = try ext == "sfc" ? SFCParser.parse(data) : DXFParser.parse(data)
        progress(WorkProgress(label: "図面の索引を作っています", fraction: 0.9))
        progress(WorkProgress(label: "図面を出しました", fraction: 1))
        return document
    }
}
