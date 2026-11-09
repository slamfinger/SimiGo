import Foundation
import XCTest
@testable import SimiGoRuntimeContract

final class PathsTests: XCTestCase {

    func testManagedRootHonorsSimigoHomeOverride() {
        let root = ManagedPaths.managedRoot(env: ["SIMIGO_HOME": "/tmp/simigo-test-root"])
        XCTAssertEqual(root.path, "/tmp/simigo-test-root")
        // Derived (no override) must not hardcode a developer absolute path in source;
        // it resolves through Foundation's current-user home.
        let derived = ManagedPaths.managedRoot(env: [:])
        XCTAssertTrue(derived.path.hasSuffix("/.simigo"))
    }

    func testNoWorkOrModelsUnderManagedRoot() {
        XCTAssertTrue(ManagedPaths.forbiddenSubdirectories.isSuperset(of: ["work", "models"]))
        for url in ManagedPaths.creatableSubdirectories {
            let name = url.lastPathComponent
            XCTAssertFalse(ManagedPaths.forbiddenSubdirectories.contains(name), "creatable set must exclude \(name)")
        }
        XCTAssertEqual(ManagedPaths.databaseURL.lastPathComponent, "simigo.sqlite3")
    }

    func testRelativeEscapeRejected() {
        let root = URL(fileURLWithPath: "/tmp/simigo-work-root", isDirectory: true)
        XCTAssertThrowsError(try ManagedPaths.RootReference(rootID: "r", relativePath: "../../etc/passwd").resolve(against: root)) { e in
            XCTAssertEqual(e as? ManagedPaths.PathError, .relativeEscape("../../etc/passwd"))
        }
        XCTAssertThrowsError(try ManagedPaths.RootReference(rootID: "r", relativePath: "a/../../outside").resolve(against: root))
    }

    func testAbsoluteInputRejected() {
        let root = URL(fileURLWithPath: "/tmp/simigo-work-root", isDirectory: true)
        XCTAssertThrowsError(try ManagedPaths.RootReference(rootID: "r", relativePath: "/etc/passwd").resolve(against: root)) { e in
            XCTAssertEqual(e as? ManagedPaths.PathError, .notRelative("/etc/passwd"))
        }
    }

    func testValidAndContainedDotDotResolveWithinRoot() throws {
        let root = URL(fileURLWithPath: "/tmp/simigo-work-root", isDirectory: true)
        let nested = try ManagedPaths.RootReference(rootID: "r", relativePath: "docs/notes.txt").resolve(against: root)
        XCTAssertEqual(nested.path, "/tmp/simigo-work-root/docs/notes.txt")
        // `a/../b` stays inside the root and is allowed.
        let stay = try ManagedPaths.RootReference(rootID: "r", relativePath: "a/../b").resolve(against: root)
        XCTAssertTrue(stay.path.hasPrefix(root.standardizedFileURL.path + "/"))
        XCTAssertEqual(stay.lastPathComponent, "b")
    }

    func testUnicodeAndSpacePathsResolve() throws {
        let root = URL(fileURLWithPath: "/tmp/simigo 工作区 ünï", isDirectory: true)
        let url = try ManagedPaths.RootReference(rootID: "r", relativePath: "子目录/file name.md").resolve(against: root)
        XCTAssertTrue(url.path.hasPrefix(root.standardizedFileURL.path))
        XCTAssertEqual(url.lastPathComponent, "file name.md")
    }

    func testHFCacheCandidatesPrecedeEnvironment() {
        let candidates = ManagedPaths.huggingFaceCacheCandidates(env: ["HF_HUB_CACHE": "/volumes/ext/hf hub"])
        XCTAssertEqual(candidates.first?.path, "/volumes/ext/hf hub")
        // With HF_HOME only, hub subdir is derived and the default remains present.
        let viaHome = ManagedPaths.huggingFaceCacheCandidates(env: ["HF_HOME": "/data/hf"])
        XCTAssertTrue(viaHome.contains { $0.path == "/data/hf/hub" })
    }
}
