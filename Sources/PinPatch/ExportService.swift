import Foundation

struct PPExportArtifact {
    let url: URL
    let cleanupRoot: URL
}

actor PPExportService {
    static let shared = PPExportService()
    private let storage: PPStorage

    init(storage: PPStorage = .shared) {
        self.storage = storage
    }

    func markdown() async throws -> String {
        let pins = try await storage.loadPinSummaries()
        let screens = try await storage.loadScreenRecords()
        let groups = try await storage.loadGroups()
        var lines = ["# PinPatch", ""]
        let activeScreens = screens.filter { screen in
            pins.contains(where: { $0.record.screenID == screen.screenID })
        }
        for (screenIndex, screen) in activeScreens.enumerated() {
            let matching = pins.filter { $0.record.screenID == screen.screenID }
            guard !matching.isEmpty else { continue }
            lines.append("## Screen \(screenIndex + 1): \(screen.fingerprint.rawTitle ?? "Untitled")")
            lines.append("")
            lines.append("- screen_id: `\(screen.screenID.uuidString.lowercased())`")
            lines.append("")
            for (pinIndex, pin) in matching.enumerated() {
                lines.append("### \(screenIndex + 1)-\(pinIndex + 1)")
                lines.append("")
                lines.append("- pin_id: `\(pin.record.pinID.uuidString.lowercased())`")
                lines.append("- revision_id: `\(pin.record.revisionID.uuidString.lowercased())`")
                if let tag = pin.record.tag { lines.append("- tag: \(tag.localizedTitle)") }
                if let value = pin.record.element.viewClass { lines.append("- view: `\(value)`") }
                if !pin.record.element.controllerChain.isEmpty {
                    lines.append("- controller_chain: \(pin.record.element.controllerChain.map { "`\($0)`" }.joined(separator: " → "))")
                }
                if let value = pin.record.element.accessibilityIdentifier { lines.append("- accessibility_id: `\(value)`") }
                if let value = pin.record.element.accessibilityLabel { lines.append("- element: \(value)") }
                if !pin.record.element.controlActions.isEmpty {
                    lines.append("- actions: \(pin.record.element.controlActions.map { "`\($0)`" }.joined(separator: ", "))")
                }
                lines.append("")
                lines.append(pin.note)
                if let result = pin.result { lines.append("\nResult: \(result.summary)") }
                lines.append("")
            }
        }
        if !groups.isEmpty {
            lines.append("## Links")
            lines.append("")
            for group in groups {
                lines.append("### \(group.groupID.uuidString.lowercased())")
                lines.append("")
                lines.append("Pins: \(group.pinIDs.map { "`\($0.uuidString.lowercased())`" }.joined(separator: ", "))")
                lines.append("")
                lines.append(group.instruction)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    func markdownFile() async throws -> PPExportArtifact {
        let root = try temporaryRoot()
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: root) } }
        let url = root.appendingPathComponent("PinPatch.md")
        try Data((try await markdown()).utf8).write(to: url, options: [.atomic])
        keep = true
        return PPExportArtifact(url: url, cleanupRoot: root)
    }

    func zip() async throws -> PPExportArtifact {
        let root = try temporaryRoot()
        var keep = false
        defer { if !keep { try? FileManager.default.removeItem(at: root) } }
        let source = root.appendingPathComponent("PinPatch", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data((try await markdown()).utf8).write(to: source.appendingPathComponent("PinPatch.md"), options: [.atomic])
        let storageRoot = try await storage.prepare()
        for name in ["manifest.json", "screens", "pins", "groups", "results"] {
            let item = storageRoot.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: item.path) else { continue }
            try FileManager.default.copyItem(at: item, to: source.appendingPathComponent(name))
        }
        let destination = root.appendingPathComponent("PinPatch.zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .forUploading, error: &coordinationError) { snapshot in
            do { try FileManager.default.moveItem(at: snapshot, to: destination) }
            catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw PPExportError.invalidArchive }
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0 else { throw PPExportError.emptyArchive }
        keep = true
        return PPExportArtifact(url: destination, cleanupRoot: root)
    }

    func cleanup(_ artifact: PPExportArtifact) {
        try? FileManager.default.removeItem(at: artifact.cleanupRoot)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PinPatchExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

enum PPExportError: Error {
    case emptyArchive
    case invalidArchive
}
