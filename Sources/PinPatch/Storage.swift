import Foundation
import Darwin

actor PPStorage {
    static let shared = PPStorage()

    private let fm = FileManager.default
    private let rootOverride: URL?
    private let faultInjector: ((PPStorageCheckpoint) throws -> Void)?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var prepared = false
    private(set) var rootURL: URL?

    init(rootURL: URL? = nil, faultInjector: ((PPStorageCheckpoint) throws -> Void)? = nil) {
        rootOverride = rootURL
        self.faultInjector = faultInjector
    }

    func prepare() throws -> URL {
        if prepared, let rootURL { return rootURL }
        let root: URL
        if let rootOverride {
            root = rootOverride
        } else {
            let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            root = support.appendingPathComponent("PinPatch", isDirectory: true)
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["screens", "pins", "groups", "results", ".staging", ".trash"] {
            try fm.createDirectory(at: root.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        }
        try applyProtection(to: root)
        try writeManifestIfNeeded(root: root)
        try cleanStaging(root: root)
        try cleanOrphanRevisions(root: root)
        try recoverScreenRegistry(root: root)
        try cleanGroups(root: root)
        try? rebuildIndex(root: root)
        rootURL = root
        prepared = true
        return root
    }

    func resolveScreen(_ fingerprint: PPScreenFingerprint) throws -> PPScreenRecord {
        let root = try prepare()
        let screensURL = root.appendingPathComponent("screens", isDirectory: true)
        let existing = try loadScreenRecords(root: root)
        if let match = existing.first(where: { $0.fingerprint.canonical == fingerprint.canonical }) {
            return match
        }
        if let match = existing.first(where: { ($0.aliases ?? []).contains(fingerprint.canonical) }) {
            let aliases = Array(Set((match.aliases ?? []) + [match.fingerprint.canonical])).sorted()
            let migrated = PPScreenRecord(
                screenID: match.screenID,
                fingerprint: fingerprint,
                firstSeenAt: match.firstSeenAt,
                firstSeenOrdinal: match.firstSeenOrdinal,
                aliases: aliases
            )
            let destination = screensURL.appendingPathComponent(match.screenID.uuidString.lowercased()).appendingPathExtension("json")
            try writeJSON(migrated, to: destination)
            return migrated
        }
        if let match = existing.first(where: {
            $0.fingerprint.versionIndependentCanonical == fingerprint.versionIndependentCanonical
        }) {
            let aliases = Array(Set((match.aliases ?? []) + [match.fingerprint.canonical])).sorted()
            let migrated = PPScreenRecord(
                screenID: match.screenID,
                fingerprint: fingerprint,
                firstSeenAt: match.firstSeenAt,
                firstSeenOrdinal: match.firstSeenOrdinal,
                aliases: aliases
            )
            let destination = screensURL.appendingPathComponent(match.screenID.uuidString.lowercased()).appendingPathExtension("json")
            try writeJSON(migrated, to: destination)
            try? rebuildIndex(root: root)
            return migrated
        }
        let record = PPScreenRecord(
            screenID: UUID(),
            fingerprint: fingerprint,
            firstSeenAt: Date(),
            firstSeenOrdinal: (existing.map(\.firstSeenOrdinal).max() ?? 0) + 1,
            aliases: nil
        )
        let destination = screensURL.appendingPathComponent(record.screenID.uuidString.lowercased()).appendingPathExtension("json")
        try writeJSON(record, to: destination)
        try? rebuildIndex(root: root)
        return record
    }

    func findScreen(_ fingerprint: PPScreenFingerprint) throws -> PPScreenRecord? {
        let root = try prepare()
        let existing = try loadScreenRecords(root: root)
        return existing.first(where: {
            $0.fingerprint.canonical == fingerprint.canonical
                || ($0.aliases ?? []).contains(fingerprint.canonical)
                || $0.fingerprint.versionIndependentCanonical == fingerprint.versionIndependentCanonical
        })
    }

    func savePin(
        screen: PPScreenRecord,
        record: PPPinRecord,
        note: String,
        screenshot: Data,
        crop: Data
    ) throws {
        let root = try prepare()
        guard screen.screenID == record.screenID else { throw PPStorageError.invalidRecord }
        let transactionID = UUID().uuidString.lowercased()
        let transaction = root.appendingPathComponent(".staging/\(transactionID)", isDirectory: true)
        let stagedPin = transaction.appendingPathComponent(record.pinID.uuidString.lowercased(), isDirectory: true)
        let assets = stagedPin.appendingPathComponent("assets", isDirectory: true)
        let revision = stagedPin.appendingPathComponent("revisions/\(record.revisionID.uuidString.lowercased())", isDirectory: true)
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        try fm.createDirectory(at: revision, withIntermediateDirectories: true)

        do {
            try writeAndValidate(screenshot, to: assets.appendingPathComponent("screen.png"))
            try writeAndValidate(crop, to: assets.appendingPathComponent("crop.png"))
            try writeJSON(record, to: revision.appendingPathComponent("pin.json"))
            try writeAndValidate(Data(note.utf8), to: revision.appendingPathComponent("note.md"))
            try writeJSON(PPCurrentRevision(revisionID: record.revisionID), to: stagedPin.appendingPathComponent("current.json"))
            try syncDirectory(stagedPin)
            try faultInjector?(.beforePinCommit)
            let destination = root.appendingPathComponent("pins/\(record.pinID.uuidString.lowercased())", isDirectory: true)
            guard !fm.fileExists(atPath: destination.path) else { throw PPStorageError.pinAlreadyExists }
            try fm.moveItem(at: stagedPin, to: destination)
            try syncDirectory(root.appendingPathComponent("pins", isDirectory: true))
            try? fm.removeItem(at: transaction)
            try? rebuildIndex(root: root)
        } catch {
            try? fm.removeItem(at: transaction)
            throw error
        }
    }

    func updateNote(pinID: UUID, note: String, tag: PPTag?) throws {
        let root = try prepare()
        let pin = root.appendingPathComponent("pins/\(pinID.uuidString.lowercased())", isDirectory: true)
        let current: PPCurrentRevision = try readJSON(at: pin.appendingPathComponent("current.json"))
        let oldRevision = pin.appendingPathComponent("revisions/\(current.revisionID.uuidString.lowercased())", isDirectory: true)
        var record: PPPinRecord = try readJSON(at: oldRevision.appendingPathComponent("pin.json"))
        guard record.pinID == pinID, record.revisionID == current.revisionID else { throw PPStorageError.invalidRecord }
        let newRevisionID = UUID()
        record = PPPinRecord(
            schemaVersion: record.schemaVersion, pinID: record.pinID, screenID: record.screenID,
            revisionID: newRevisionID, createdAt: record.createdAt, sceneSessionID: record.sceneSessionID,
            normalizedPoint: record.normalizedPoint, targetFrame: record.targetFrame, tag: tag,
            fingerprint: record.fingerprint, element: record.element, interfaceStyle: record.interfaceStyle,
            orientation: record.orientation, displayScale: record.displayScale
        )
        let staging = pin.appendingPathComponent(".revision-\(newRevisionID.uuidString.lowercased())", isDirectory: true)
        let finalRevision = pin.appendingPathComponent("revisions/\(newRevisionID.uuidString.lowercased())", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try writeJSON(record, to: staging.appendingPathComponent("pin.json"))
            try writeAndValidate(Data(note.utf8), to: staging.appendingPathComponent("note.md"))
            try syncDirectory(staging)
            try fm.moveItem(at: staging, to: finalRevision)
            try syncDirectory(pin.appendingPathComponent("revisions", isDirectory: true))
            try faultInjector?(.afterRevisionCommitBeforeCurrentSwap)
            try atomicReplaceJSON(PPCurrentRevision(revisionID: newRevisionID), at: pin.appendingPathComponent("current.json"))
            try? fm.removeItem(at: root.appendingPathComponent("results/\(pinID.uuidString.lowercased()).json"))
            try cleanRevisions(in: pin, keeping: newRevisionID)
            try? rebuildIndex(root: root)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    func deletePin(_ pinID: UUID) throws {
        let root = try prepare()
        let source = root.appendingPathComponent("pins/\(pinID.uuidString.lowercased())", isDirectory: true)
        guard fm.fileExists(atPath: source.path) else { return }
        let trash = root.appendingPathComponent(".trash/\(UUID().uuidString.lowercased())", isDirectory: true)
        try fm.moveItem(at: source, to: trash)
        try? fm.removeItem(at: root.appendingPathComponent("results/\(pinID.uuidString.lowercased()).json"))
        try pruneGroups(removing: pinID, root: root)
        try? fm.removeItem(at: trash)
        try? rebuildIndex(root: root)
    }

    func deleteAll() throws {
        let root = try prepare()
        for name in ["screens", "pins", "groups", "results", ".staging", ".trash"] {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try? fm.removeItem(at: url)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try? fm.removeItem(at: root.appendingPathComponent("index.json"))
        try rebuildIndex(root: root)
    }

    func createGroup(pinIDs: [UUID], instruction: String) throws -> PPGroupRecord {
        let root = try prepare()
        let uniqueIDs = Array(Set(pinIDs)).sorted { $0.uuidString < $1.uuidString }
        guard uniqueIDs.count >= 2, uniqueIDs.allSatisfy({
            fm.fileExists(atPath: root.appendingPathComponent("pins/\($0.uuidString.lowercased())").path)
        }) else { throw PPStorageError.invalidGroup }
        let record = PPGroupRecord(schemaVersion: 1, groupID: UUID(), pinIDs: uniqueIDs, createdAt: Date(), instruction: instruction)
        let transaction = root.appendingPathComponent(".staging/group-\(UUID().uuidString.lowercased())", isDirectory: true)
        let staged = transaction.appendingPathComponent(record.groupID.uuidString.lowercased(), isDirectory: true)
        let destination = root.appendingPathComponent("groups/\(record.groupID.uuidString.lowercased())", isDirectory: true)
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        do {
            try writeJSON(record, to: staged.appendingPathComponent("group.json"))
            try writeAndValidate(Data(instruction.utf8), to: staged.appendingPathComponent("note.md"))
            try syncDirectory(staged)
            try fm.moveItem(at: staged, to: destination)
            try syncDirectory(root.appendingPathComponent("groups", isDirectory: true))
            try? fm.removeItem(at: transaction)
            try? rebuildIndex(root: root)
            return record
        } catch {
            try? fm.removeItem(at: transaction)
            throw error
        }
    }

    func loadPinSummaries() throws -> [PPPinSummary] {
        let root = try prepare()
        let pinsURL = root.appendingPathComponent("pins", isDirectory: true)
        let folders = (try? fm.contentsOfDirectory(at: pinsURL, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let pinID = UUID(uuidString: folder.lastPathComponent),
                  let current: PPCurrentRevision = try? readJSON(at: folder.appendingPathComponent("current.json")) else { return nil }
            let revision = folder.appendingPathComponent("revisions/\(current.revisionID.uuidString.lowercased())", isDirectory: true)
            guard let record: PPPinRecord = try? readJSON(at: revision.appendingPathComponent("pin.json")),
                  record.pinID == pinID, record.revisionID == current.revisionID,
                  let note = try? String(contentsOf: revision.appendingPathComponent("note.md"), encoding: .utf8) else { return nil }
            let resultURL = root.appendingPathComponent("results/\(pinID.uuidString.lowercased()).json")
            let result: PPResultRecord? = try? readJSON(at: resultURL)
            return PPPinSummary(
                record: record,
                note: note,
                result: result?.processedRevisionID == current.revisionID ? result : nil,
                cropURL: folder.appendingPathComponent("assets/crop.png")
            )
        }.sorted { $0.record.createdAt < $1.record.createdAt }
    }

    func loadGroups() throws -> [PPGroupRecord] {
        let root = try prepare()
        let folders = (try? fm.contentsOfDirectory(at: root.appendingPathComponent("groups"), includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { try? readJSON(at: $0.appendingPathComponent("group.json")) }
    }

    func loadScreenRecords() throws -> [PPScreenRecord] {
        try loadScreenRecords(root: prepare()).sorted { $0.firstSeenOrdinal < $1.firstSeenOrdinal }
    }

    private func loadScreenRecords(root: URL) throws -> [PPScreenRecord] {
        let files = (try? fm.contentsOfDirectory(at: root.appendingPathComponent("screens"), includingPropertiesForKeys: nil)) ?? []
        var records = files.compactMap { try? readJSON(PPScreenRecord.self, at: $0) }
        var known = Set(records.map(\.screenID))
        let pins = try? loadPinSummariesWithoutPrepare(root: root)
        for summary in pins ?? [] where known.insert(summary.record.screenID).inserted {
            records.append(PPScreenRecord(
                screenID: summary.record.screenID,
                fingerprint: summary.record.fingerprint,
                firstSeenAt: summary.record.createdAt,
                firstSeenOrdinal: records.count + 1,
                aliases: nil
            ))
        }
        return records
    }

    private func loadPinSummariesWithoutPrepare(root: URL) throws -> [PPPinSummary] {
        let folders = (try? fm.contentsOfDirectory(at: root.appendingPathComponent("pins"), includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let folderPinID = UUID(uuidString: folder.lastPathComponent) else { return nil }
            guard let current: PPCurrentRevision = try? readJSON(at: folder.appendingPathComponent("current.json")) else { return nil }
            let revision = folder.appendingPathComponent("revisions/\(current.revisionID.uuidString.lowercased())")
            guard let record: PPPinRecord = try? readJSON(at: revision.appendingPathComponent("pin.json")),
                  record.pinID == folderPinID, record.revisionID == current.revisionID,
                  let note = try? String(contentsOf: revision.appendingPathComponent("note.md"), encoding: .utf8) else { return nil }
            return PPPinSummary(
                record: record,
                note: note,
                result: nil,
                cropURL: folder.appendingPathComponent("assets/crop.png")
            )
        }
    }

    private func writeManifestIfNeeded(root: URL) throws {
        let url = root.appendingPathComponent("manifest.json")
        guard !fm.fileExists(atPath: url.path) else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        let manifest = PPManifest(
            schemaVersion: 1,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            createdAt: Date()
        )
        try writeJSON(manifest, to: url)
    }

    private func applyProtection(to root: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = root
        try mutable.setResourceValues(values)
        try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try writeAndValidate(encoder.encode(value), to: url)
    }

    private func atomicReplaceJSON<T: Encodable>(_ value: T, at url: URL) throws {
        try writeJSON(value, to: url)
    }

    private func readJSON<T: Decodable>(_ type: T.Type = T.self, at url: URL) throws -> T {
        try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func writeAndValidate(_ data: Data, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".\(UUID().uuidString.lowercased()).tmp")
        guard fm.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        ) else { throw PPStorageError.cannotCreateFile }
        var handle: FileHandle?
        do {
            handle = try FileHandle(forWritingTo: temporary)
            try handle?.write(contentsOf: data)
            try handle?.synchronize()
            try handle?.close()
            handle = nil
            let attributes = try fm.attributesOfItem(atPath: temporary.path)
            guard (attributes[.size] as? NSNumber)?.intValue == data.count else { throw PPStorageError.incompleteWrite }
            try atomicRename(temporary, to: url)
            try syncDirectory(parent)
        } catch {
            try? handle?.close()
            try? fm.removeItem(at: temporary)
            throw error
        }
    }

    private func atomicRename(_ source: URL, to destination: URL) throws {
        let status = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return Int32(-1) }
                return Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard status == 0 else { throw PPStorageError.cannotCommit }
    }

    private func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw PPStorageError.cannotSynchronize }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw PPStorageError.cannotSynchronize }
    }

    private func cleanStaging(root: URL) throws {
        for name in [".staging", ".trash"] {
            for url in (try? fm.contentsOfDirectory(at: root.appendingPathComponent(name), includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func recoverScreenRegistry(root: URL) throws {
        let screenDirectory = root.appendingPathComponent("screens", isDirectory: true)
        let files = (try? fm.contentsOfDirectory(at: screenDirectory, includingPropertiesForKeys: nil)) ?? []
        var records = files.compactMap { try? readJSON(PPScreenRecord.self, at: $0) }
        let summaries = try loadPinSummariesWithoutPrepare(root: root)
        var knownIDs = Set(records.map(\.screenID))
        var nextOrdinal = (records.map(\.firstSeenOrdinal).max() ?? 0) + 1
        for summary in summaries.sorted(by: { $0.record.createdAt < $1.record.createdAt })
        where knownIDs.insert(summary.record.screenID).inserted {
            let recovered = PPScreenRecord(
                screenID: summary.record.screenID,
                fingerprint: summary.record.fingerprint,
                firstSeenAt: summary.record.createdAt,
                firstSeenOrdinal: nextOrdinal,
                aliases: nil
            )
            records.append(recovered)
            nextOrdinal += 1
            try writeJSON(
                recovered,
                to: screenDirectory.appendingPathComponent(summary.record.screenID.uuidString.lowercased()).appendingPathExtension("json")
            )
        }
    }

    private func cleanGroups(root: URL) throws {
        let validPinIDs = Set(((try? fm.contentsOfDirectory(
            at: root.appendingPathComponent("pins", isDirectory: true),
            includingPropertiesForKeys: nil
        )) ?? []).compactMap { UUID(uuidString: $0.lastPathComponent) })
        let groups = (try? fm.contentsOfDirectory(at: root.appendingPathComponent("groups"), includingPropertiesForKeys: nil)) ?? []
        for folder in groups {
            guard let group: PPGroupRecord = try? readJSON(at: folder.appendingPathComponent("group.json")) else { continue }
            let remaining = group.pinIDs.filter(validPinIDs.contains)
            if remaining.count < 2 {
                try? fm.removeItem(at: folder)
            } else {
                if remaining.count != group.pinIDs.count {
                    let updated = PPGroupRecord(
                        schemaVersion: group.schemaVersion,
                        groupID: group.groupID,
                        pinIDs: remaining,
                        createdAt: group.createdAt,
                        instruction: group.instruction
                    )
                    try atomicReplaceJSON(updated, at: folder.appendingPathComponent("group.json"))
                }
                let note = folder.appendingPathComponent("note.md")
                if !fm.fileExists(atPath: note.path) {
                    try writeAndValidate(Data(group.instruction.utf8), to: note)
                }
            }
        }
    }

    private func cleanOrphanRevisions(root: URL) throws {
        let pins = (try? fm.contentsOfDirectory(at: root.appendingPathComponent("pins"), includingPropertiesForKeys: nil)) ?? []
        for pin in pins {
            guard let current: PPCurrentRevision = try? readJSON(at: pin.appendingPathComponent("current.json")) else { continue }
            try cleanRevisions(in: pin, keeping: current.revisionID)
            for file in (try? fm.contentsOfDirectory(at: pin, includingPropertiesForKeys: nil)) ?? [] where file.lastPathComponent.hasPrefix(".revision-") {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func cleanRevisions(in pin: URL, keeping revisionID: UUID) throws {
        let revisions = pin.appendingPathComponent("revisions", isDirectory: true)
        for url in (try? fm.contentsOfDirectory(at: revisions, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent != revisionID.uuidString.lowercased() {
            try? fm.removeItem(at: url)
        }
    }

    private func pruneGroups(removing pinID: UUID, root: URL) throws {
        let groups = (try? fm.contentsOfDirectory(at: root.appendingPathComponent("groups"), includingPropertiesForKeys: nil)) ?? []
        for folder in groups {
            guard let group: PPGroupRecord = try? readJSON(at: folder.appendingPathComponent("group.json")) else { continue }
            let remaining = group.pinIDs.filter { $0 != pinID }
            if remaining.count < 2 {
                try? fm.removeItem(at: folder)
            } else if remaining.count != group.pinIDs.count {
                let updated = PPGroupRecord(schemaVersion: group.schemaVersion, groupID: group.groupID, pinIDs: remaining, createdAt: group.createdAt, instruction: group.instruction)
                try atomicReplaceJSON(updated, at: folder.appendingPathComponent("group.json"))
            }
        }
    }

    private func rebuildIndex(root: URL) throws {
        func ids(in name: String, extension ext: String? = nil) -> [UUID] {
            let files = (try? fm.contentsOfDirectory(at: root.appendingPathComponent(name), includingPropertiesForKeys: nil)) ?? []
            return files.compactMap { url in
                let candidate = ext == nil ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
                return UUID(uuidString: candidate)
            }.sorted { $0.uuidString < $1.uuidString }
        }
        let index = PPIndexCache(
            generatedAt: Date(), screenIDs: ids(in: "screens", extension: "json"), pinIDs: ids(in: "pins"),
            groupIDs: ids(in: "groups"), resultPinIDs: ids(in: "results", extension: "json")
        )
        try atomicReplaceJSON(index, at: root.appendingPathComponent("index.json"))
    }
}

enum PPStorageError: Error {
    case pinAlreadyExists
    case invalidRecord
    case invalidGroup
    case incompleteWrite
    case cannotCreateFile
    case cannotSynchronize
    case cannotCommit
}

enum PPStorageCheckpoint: Sendable, Equatable {
    case beforePinCommit
    case afterRevisionCommitBeforeCurrentSwap
}
