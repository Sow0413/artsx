import XCTest
@testable import SurveyCore

final class ProjectSheetTests: XCTestCase {
    func testSheetStaysWithTheProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sheet-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try ProjectStore.create(name: "現場", at: root)
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let saved = try ProjectStore.saveSheet(data: png, fileName: "図面.png", kind: "image", projectName: project.name, at: root)
        XCTAssertEqual(saved.fileName, "図面.png")
        XCTAssertEqual(saved.byteCount, png.count)
        let loaded = ProjectStore.loadSheet(projectName: project.name, at: root)
        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(ProjectStore.sheetData(projectName: project.name, at: root), png)
    }
}
