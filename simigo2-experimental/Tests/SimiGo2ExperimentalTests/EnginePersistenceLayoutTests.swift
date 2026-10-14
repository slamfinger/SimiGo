import CryptoKit
import XCTest
@testable import SimiGo2Experimental

final class EnginePersistenceLayoutTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-persistence-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDirectoriesAreDeterministicAndModelScoped() throws {
        let model = root.appendingPathComponent("model-a")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)

        let first = try OversizedEnginePersistence.directories(
            modelDirectory: model, baseDirectory: root)
        let second = try OversizedEnginePersistence.directories(
            modelDirectory: model.standardizedFileURL, baseDirectory: root)
        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.sessionBaseline.standardizedFileURL.path,
            root.appendingPathComponent("engines").appendingPathComponent(
                SHA256.hash(data: Data(model.standardizedFileURL.path.utf8))
                    .map { String(format: "%02x", $0) }.joined()
            ).appendingPathComponent("baseline").standardizedFileURL.path)
        XCTAssertEqual(first.identity.lastPathComponent, "identity")

        let other = try OversizedEnginePersistence.directories(
            modelDirectory: root.appendingPathComponent("model-b"), baseDirectory: root)
        XCTAssertNotEqual(first.sessionBaseline, other.sessionBaseline)
        XCTAssertNotEqual(first.identity, other.identity)
    }
}
