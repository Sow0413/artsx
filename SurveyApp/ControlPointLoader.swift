import Foundation
import SurveyCore

enum ControlPointLoader {
    /// 現場パックの `control-points.json`（無ければ CSV）を先に使う。無ければ同梱の見本。
    static func load(siteDirectory: URL, bundle: Bundle = .main) -> (points: [ControlPoint], notice: String?) {
        let json = siteDirectory.appendingPathComponent("control-points.json")
        let csv = siteDirectory.appendingPathComponent("control-points.csv")
        if FileManager.default.fileExists(atPath: json.path) {
            return loadFile(json, csvText: false)
        }
        if FileManager.default.fileExists(atPath: csv.path) {
            return loadFile(csv, csvText: true)
        }
        guard let url = bundledSampleURL(bundle),
              let data = try? Data(contentsOf: url),
              let points = try? ControlPointCatalog.loadJSON(data) else {
            return ([], "基準点の見本を読めませんでした。")
        }
        return (points, nil)
    }

    private static func loadFile(_ url: URL, csvText: Bool) -> (points: [ControlPoint], notice: String?) {
        if csvText {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let points = try? ControlPointCatalog.loadCSV(text),
                  !points.isEmpty else {
                return ([], "現場パックの基準点を読めませんでした。")
            }
            return (points, nil)
        }
        guard let data = try? Data(contentsOf: url),
              let points = try? ControlPointCatalog.loadJSON(data),
              !points.isEmpty else {
            return ([], "現場パックの基準点を読めませんでした。")
        }
        return (points, nil)
    }

    /// Xcode のアプリは main。Swift Playgrounds のパッケージは module に資源を置く。
    private static func bundledSampleURL(_ bundle: Bundle) -> URL? {
        if let url = bundle.url(forResource: "sample-control-points", withExtension: "json") {
            return url
        }
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "sample-control-points", withExtension: "json")
        #else
        return nil
        #endif
    }
}
