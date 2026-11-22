import Foundation

public enum ReadStatus: String, Codable, Equatable, Sendable {
    case reportedComplete
    case partial
    case unknown
}

public enum SizeCaliber: String, Codable, Equatable, Sendable {
    case logical
    case allocated
}

public enum ActivityStatus: String, Codable, Equatable, Sendable {
    /// This checkpoint always uses notCollected. Gaze must not become "recording".
    case notCollected
}

public struct SnapshotItem: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var bytes: Int64?
    public var errorCount: Int
    public var readStatus: ReadStatus

    public init(id: String, name: String, bytes: Int64?, errorCount: Int, readStatus: ReadStatus) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.errorCount = errorCount
        self.readStatus = readStatus
    }

    /// Unknown is not zero. A missing or non-finite value stays nil.
    public var knownBytes: Int64? {
        guard let bytes, bytes >= 0 else { return nil }
        return bytes
    }

    public var isPartial: Bool { readStatus == .partial }
    public var isUnknown: Bool { readStatus == .unknown || knownBytes == nil }
}

public struct FolderLogicalProof: Codable, Equatable, Sendable {
    public var snapshotID:String, rootPath:String
    public var complete:Bool, stableDeviceInodeOwnership:Bool
    public var bucketTotal:Int64
    public init(snapshotID:String,rootPath:String,complete:Bool,stableDeviceInodeOwnership:Bool,bucketTotal:Int64){self.snapshotID=snapshotID;self.rootPath=rootPath;self.complete=complete;self.stableDeviceInodeOwnership=stableDeviceInodeOwnership;self.bucketTotal=bucketTotal}
}

public struct DemoSnapshot: Codable, Equatable, Sendable {
    public var id: String
    /// Production snapshots must be false. Test geometry fixtures must be true and must not be used for on-screen production data.
    public var testOnly: Bool
    /// Independent example-interaction source. Never mixed into the real Eric du snapshot.
    /// The on-screen five-sector preview loads this role only; it is not a testOnly fixture.
    public var exampleInteraction: Bool
    public var label: String
    public var startedAt: Date
    public var endedAt: Date
    public var timeZoneName: String
    public var caliber: SizeCaliber
    public var caliberNote: String
    public var apfsRootDataDedupVerified: Bool
    public var nonOverlapVerified: Bool
    public var activity: ActivityStatus
    public var notes: [String]
    public var items: [SnapshotItem]
    public var folderLogicalProof:FolderLogicalProof?

    public init(
        id: String,
        testOnly: Bool,
        exampleInteraction: Bool = false,
        label: String,
        startedAt: Date,
        endedAt: Date,
        timeZoneName: String,
        caliber: SizeCaliber,
        caliberNote: String,
        apfsRootDataDedupVerified: Bool,
        nonOverlapVerified: Bool,
        activity: ActivityStatus,
        notes: [String],
        items: [SnapshotItem],
        folderLogicalProof:FolderLogicalProof? = nil
    ) {
        self.id = id
        self.testOnly = testOnly
        self.exampleInteraction = exampleInteraction
        self.label = label
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.timeZoneName = timeZoneName
        self.caliber = caliber
        self.caliberNote = caliberNote
        self.apfsRootDataDedupVerified = apfsRootDataDedupVerified
        self.nonOverlapVerified = nonOverlapVerified
        self.activity = activity
        self.notes = notes
        self.items = items
        self.folderLogicalProof = folderLogicalProof
    }
}

extension DemoSnapshot {
    enum CodingKeys: String, CodingKey {
        case folderLogicalProof
        case id, testOnly, exampleInteraction, label, startedAt, endedAt, timeZoneName
        case caliber, caliberNote, apfsRootDataDedupVerified, nonOverlapVerified, activity, notes, items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folderLogicalProof = try c.decodeIfPresent(FolderLogicalProof.self,forKey:.folderLogicalProof)
        id = try c.decode(String.self, forKey: .id)
        testOnly = try c.decode(Bool.self, forKey: .testOnly)
        exampleInteraction = try c.decodeIfPresent(Bool.self, forKey: .exampleInteraction) ?? false
        label = try c.decode(String.self, forKey: .label)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        timeZoneName = try c.decode(String.self, forKey: .timeZoneName)
        caliber = try c.decode(SizeCaliber.self, forKey: .caliber)
        caliberNote = try c.decode(String.self, forKey: .caliberNote)
        apfsRootDataDedupVerified = try c.decode(Bool.self, forKey: .apfsRootDataDedupVerified)
        nonOverlapVerified = try c.decode(Bool.self, forKey: .nonOverlapVerified)
        activity = try c.decode(ActivityStatus.self, forKey: .activity)
        notes = try c.decode([String].self, forKey: .notes)
        items = try c.decode([SnapshotItem].self, forKey: .items)
        if testOnly && exampleInteraction {
            throw SnapshotLoadError.rejectedMixedRoles
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(folderLogicalProof,forKey:.folderLogicalProof)
        try c.encode(id, forKey: .id)
        try c.encode(testOnly, forKey: .testOnly)
        try c.encode(exampleInteraction, forKey: .exampleInteraction)
        try c.encode(label, forKey: .label)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(timeZoneName, forKey: .timeZoneName)
        try c.encode(caliber, forKey: .caliber)
        try c.encode(caliberNote, forKey: .caliberNote)
        try c.encode(apfsRootDataDedupVerified, forKey: .apfsRootDataDedupVerified)
        try c.encode(nonOverlapVerified, forKey: .nonOverlapVerified)
        try c.encode(activity, forKey: .activity)
        try c.encode(notes, forKey: .notes)
        try c.encode(items, forKey: .items)
    }
}

public enum SnapshotLoadError: Error, Equatable {
    case resourceMissing(String)
    case decodingFailed(String)
    case rejectedTestOnlyInProduction
    case rejectedProductionAsFixture
    case rejectedMixedRoles
    case rejectedExampleAsProduction
    case rejectedTestOnlyAsExample
    case rejectedProductionAsExample
}

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
    return f
}()

public enum SnapshotLoader {
    public static func decode(_ data: Data) throws -> DemoSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = isoFormatter.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid date \(raw)")
        }
        return try decoder.decode(DemoSnapshot.self, from: data)
    }

    /// Production demo default: the delivered Eric read-only du snapshot bundled with the core.
    public static func loadBundledProduction() throws -> DemoSnapshot {
        let snapshot = try loadBundledResource(named: "eric-du-20261121-readonly.json")
        if snapshot.testOnly { throw SnapshotLoadError.rejectedTestOnlyInProduction }
        if snapshot.exampleInteraction { throw SnapshotLoadError.rejectedExampleAsProduction }
        return snapshot
    }

    /// On-screen five-sector preview source. Isolated from the real Eric du snapshot
    /// and from the testOnly geometry fixture.
    public static func loadBundledExampleInteraction() throws -> DemoSnapshot {
        let snapshot = try loadBundledResource(named: "example-interaction-five-sectors.json")
        if snapshot.testOnly { throw SnapshotLoadError.rejectedTestOnlyAsExample }
        if !snapshot.exampleInteraction { throw SnapshotLoadError.rejectedProductionAsExample }
        return snapshot
    }

    public static func loadBundledResource(named name: String) throws -> DemoSnapshot {
        let bundle = Bundle.module
        let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Resources")
            ?? bundle.url(forResource: name, withExtension: nil)
            ?? bundle.resourceURL?.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent(name)
        guard let url else { throw SnapshotLoadError.resourceMissing(name) }
        do {
            return try decode(Data(contentsOf: url))
        } catch let err as SnapshotLoadError {
            throw err
        } catch {
            throw SnapshotLoadError.decodingFailed(String(describing: error))
        }
    }
}
