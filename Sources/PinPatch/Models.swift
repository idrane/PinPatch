import CoreGraphics
import Foundation
import UIKit

enum PPTag: String, CaseIterable, Codable, Sendable {
    case bug
    case color
    case size
    case spacing
    case text
    case behavior
    case other

    var localizedTitle: String {
        switch self {
        case .bug: return "Bug"
        case .color: return "Color"
        case .size: return "Size"
        case .spacing: return "Spacing"
        case .text: return "Text"
        case .behavior: return "Behavior"
        case .other: return "Other"
        }
    }
}

struct PPScreenFingerprint: Codable, Hashable, Sendable {
    static let version = 3

    let rawTitle: String?
    let normalizedTitle: String?
    let fingerprintVersion: Int

    var canonical: String {
        [
            "v=\(fingerprintVersion)",
            "title=\(normalizedTitle ?? "")"
        ].joined(separator: "|")
    }

    var versionIndependentCanonical: String {
        [
            "title=\(normalizedTitle ?? "")"
        ].joined(separator: "|")
    }
}

struct PPScreenRecord: Codable, Sendable {
    let screenID: UUID
    let fingerprint: PPScreenFingerprint
    let firstSeenAt: Date
    let firstSeenOrdinal: Int
    let aliases: [String]?

    init(
        screenID: UUID,
        fingerprint: PPScreenFingerprint,
        firstSeenAt: Date,
        firstSeenOrdinal: Int,
        aliases: [String]? = nil
    ) {
        self.screenID = screenID
        self.fingerprint = fingerprint
        self.firstSeenAt = firstSeenAt
        self.firstSeenOrdinal = firstSeenOrdinal
        self.aliases = aliases
    }
}

struct PPElementHint: Codable, Sendable {
    let viewClass: String?
    let moduleName: String?
    let controllerChain: [String]
    let accessibilityIdentifier: String?
    let accessibilityLabel: String?
    let accessibilityValue: String?
    let accessibilityTraits: UInt64
    let controlActions: [String]
}

struct PPNormalizedPoint: Codable, Sendable {
    let x: Double
    let y: Double
}

struct PPRect: Codable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }
}

struct PPPinRecord: Codable, Sendable {
    let schemaVersion: Int
    let pinID: UUID
    let screenID: UUID
    let revisionID: UUID
    let createdAt: Date
    let sceneSessionID: String
    let normalizedPoint: PPNormalizedPoint
    let targetFrame: PPRect?
    let tag: PPTag?
    let fingerprint: PPScreenFingerprint
    let element: PPElementHint
    let interfaceStyle: String
    let orientation: Int
    let displayScale: Double
}

struct PPCurrentRevision: Codable, Sendable {
    let revisionID: UUID
}

struct PPGroupRecord: Codable, Sendable {
    let schemaVersion: Int
    let groupID: UUID
    let pinIDs: [UUID]
    let createdAt: Date
    let instruction: String
}

enum PPResultStatus: String, Codable, Sendable {
    case resolved
    case noChange = "no-change"
    case blocked
}

struct PPResultRecord: Codable, Sendable {
    let pinID: UUID
    let processedRevisionID: UUID
    let status: PPResultStatus
    let summary: String
}

struct PPManifest: Codable, Sendable {
    let schemaVersion: Int
    let bundleIdentifier: String
    let appVersion: String
    let createdAt: Date
}

struct PPIndexCache: Codable, Sendable {
    let generatedAt: Date
    let screenIDs: [UUID]
    let pinIDs: [UUID]
    let groupIDs: [UUID]
    let resultPinIDs: [UUID]
}

struct PPPinSummary: Sendable {
    let record: PPPinRecord
    let note: String
    let result: PPResultRecord?
    let cropURL: URL
}
