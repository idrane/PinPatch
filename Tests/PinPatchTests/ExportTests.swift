import Foundation
import XCTest
@testable import PinPatch

final class ExportTests: XCTestCase {
    func testSystemFolderUploadProducesNonemptyZipAndUUIDMarkdown() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinPatchExportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PPStorage(rootURL: root)
        let fingerprint = PPScreenFingerprint(
            rawTitle: nil,
            normalizedTitle: nil,
            fingerprintVersion: 1
        )
        let screen = try await storage.resolveScreen(fingerprint)
        let pinID = UUID()
        let revisionID = UUID()
        let pin = PPPinRecord(
            schemaVersion: 1,
            pinID: pinID,
            screenID: screen.screenID,
            revisionID: revisionID,
            createdAt: Date(),
            sceneSessionID: "fixture",
            normalizedPoint: PPNormalizedPoint(x: 0.2, y: 0.3),
            targetFrame: nil,
            tag: .color,
            fingerprint: fingerprint,
            element: PPElementHint(
                viewClass: nil,
                moduleName: nil,
                controllerChain: [],
                accessibilityIdentifier: "accent",
                accessibilityLabel: "강조색",
                accessibilityValue: nil,
                accessibilityTraits: 0,
                controlActions: []
            ),
            interfaceStyle: "dark",
            orientation: 1,
            displayScale: 3
        )
        try await storage.savePin(
            screen: screen,
            record: pin,
            note: "두 요소를 같은 색으로",
            screenshot: Data("screen".utf8),
            crop: Data("crop".utf8)
        )

        let exporter = PPExportService(storage: storage)
        let markdown = try await exporter.markdown()
        XCTAssertTrue(markdown.contains(pinID.uuidString.lowercased()))
        XCTAssertTrue(markdown.contains(revisionID.uuidString.lowercased()))

        let artifact = try await exporter.zip()
        defer { Task { await exporter.cleanup(artifact) } }
        let archive = try Data(contentsOf: artifact.url)
        XCTAssertGreaterThan(archive.count, 4)
        XCTAssertEqual(Array(archive.prefix(2)), [0x50, 0x4b])
    }
}
