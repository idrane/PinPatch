import Foundation
import XCTest
@testable import PinPatch

final class StorageTests: XCTestCase {
    func testRootIsExcludedFromBackup() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PPStorage(rootURL: root)
        let prepared = try await storage.prepare()
        let values = try prepared.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testScreenIDSurvivesVersionMigrationAndRestart() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PPStorage(rootURL: root)
        let legacy = fingerprint(version: 0)
        let first = try await storage.resolveScreen(legacy)
        let current = try await storage.resolveScreen(fingerprint(version: 1))
        XCTAssertEqual(first.screenID, current.screenID)
        XCTAssertTrue(current.aliases?.contains(legacy.canonical) == true)

        let restarted = PPStorage(rootURL: root)
        let afterRestart = try await restarted.resolveScreen(fingerprint(version: 1))
        XCTAssertEqual(first.screenID, afterRestart.screenID)
    }

    func testFailedPinCommitLeavesNoVisiblePin() async throws {
        enum Injected: Error { case stop }
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PPStorage(rootURL: root) { point in
            if point == .beforePinCommit { throw Injected.stop }
        }
        let screen = try await storage.resolveScreen(fingerprint())
        let record = pin(screenID: screen.screenID)
        do {
            try await storage.savePin(
                screen: screen,
                record: record,
                note: "색을 바꿔주세요",
                screenshot: Data("screen".utf8),
                crop: Data("crop".utf8)
            )
            XCTFail("The injected failure must escape the transaction")
        } catch is Injected {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: root.appendingPathComponent("pins/\(record.pinID.uuidString.lowercased())").path
            ))
        }
    }

    func testRevisionSwapIsAtomicAndStartupRemovesOrphan() async throws {
        enum Injected: Error { case stop }
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let initialStorage = PPStorage(rootURL: root)
        let screen = try await initialStorage.resolveScreen(fingerprint())
        let original = pin(screenID: screen.screenID)
        try await initialStorage.savePin(
            screen: screen,
            record: original,
            note: "원래 메모",
            screenshot: Data("screen".utf8),
            crop: Data("crop".utf8)
        )

        let interrupted = PPStorage(rootURL: root) { point in
            if point == .afterRevisionCommitBeforeCurrentSwap { throw Injected.stop }
        }
        do {
            try await interrupted.updateNote(pinID: original.pinID, note: "새 메모", tag: .text)
            XCTFail("The injected failure must interrupt before current.json changes")
        } catch is Injected {}

        let recovered = PPStorage(rootURL: root)
        _ = try await recovered.prepare()
        let summaries = try await recovered.loadPinSummaries()
        XCTAssertEqual(summaries.first?.record.revisionID, original.revisionID)
        XCTAssertEqual(summaries.first?.note, "원래 메모")
        let revisions = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("pins/\(original.pinID.uuidString.lowercased())/revisions"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(revisions.map(\.lastPathComponent), [original.revisionID.uuidString.lowercased()])
    }

    func testRegistryAndIndexRebuildFromCanonicalPinFolders() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PPStorage(rootURL: root)
        let screen = try await storage.resolveScreen(fingerprint())
        let record = pin(screenID: screen.screenID)
        try await storage.savePin(
            screen: screen,
            record: record,
            note: "간격 수정",
            screenshot: Data("screen".utf8),
            crop: Data("crop".utf8)
        )
        try FileManager.default.removeItem(
            at: root.appendingPathComponent("screens/\(screen.screenID.uuidString.lowercased()).json")
        )
        try Data("broken".utf8).write(to: root.appendingPathComponent("index.json"))

        let recovered = PPStorage(rootURL: root)
        _ = try await recovered.prepare()
        let recoveredScreenIDs = try await recovered.loadScreenRecords().map(\.screenID)
        XCTAssertEqual(recoveredScreenIDs, [screen.screenID])
        let indexData = try Data(contentsOf: root.appendingPathComponent("index.json"))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: indexData))
    }

    func testCrossScreenGroupUsesUUIDsAndIsPrunedBelowTwoPins() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PPStorage(rootURL: root)
        let firstScreen = try await storage.resolveScreen(fingerprint(title: "301호"))
        let secondScreen = try await storage.resolveScreen(fingerprint(title: "302호"))
        let firstPin = pin(screenID: firstScreen.screenID, fingerprint: firstScreen.fingerprint)
        let secondPin = pin(screenID: secondScreen.screenID, fingerprint: secondScreen.fingerprint)
        for (screen, record) in [(firstScreen, firstPin), (secondScreen, secondPin)] {
            try await storage.savePin(
                screen: screen,
                record: record,
                note: "같은 색으로",
                screenshot: Data("screen".utf8),
                crop: Data("crop".utf8)
            )
        }
        let group = try await storage.createGroup(
            pinIDs: [secondPin.pinID, firstPin.pinID],
            instruction: "두 핀을 같은 강조색으로"
        )
        XCTAssertEqual(Set(group.pinIDs), Set([firstPin.pinID, secondPin.pinID]))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("groups/\(group.groupID.uuidString.lowercased())/group.json").path
        ))

        try await storage.deletePin(firstPin.pinID)
        let remainingGroups = try await storage.loadGroups()
        XCTAssertTrue(remainingGroups.isEmpty)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PinPatchTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func fingerprint(version: Int = 1, title: String = "301호") -> PPScreenFingerprint {
        PPScreenFingerprint(
            framework: .uiKit,
            screenKind: "Fixture.DetailViewController",
            swiftUIRootType: nil,
            swiftUISemanticDigest: nil,
            rawTitle: title,
            normalizedTitle: title,
            isModal: false,
            fingerprintVersion: version
        )
    }

    private func pin(screenID: UUID, fingerprint: PPScreenFingerprint? = nil) -> PPPinRecord {
        PPPinRecord(
            schemaVersion: 1,
            pinID: UUID(),
            screenID: screenID,
            revisionID: UUID(),
            createdAt: Date(),
            sceneSessionID: "fixture-scene",
            normalizedPoint: PPNormalizedPoint(x: 0.5, y: 0.5),
            targetFrame: nil,
            tag: .spacing,
            fingerprint: fingerprint ?? self.fingerprint(),
            element: PPElementHint(
                viewClass: "UIButton",
                moduleName: "UIKit",
                controllerChain: ["Fixture.DetailViewController"],
                accessibilityIdentifier: "save-button",
                accessibilityLabel: "저장",
                accessibilityValue: nil,
                accessibilityTraits: 1,
                controlActions: ["save:"]
            ),
            interfaceStyle: "light",
            orientation: 1,
            displayScale: 3
        )
    }
}
