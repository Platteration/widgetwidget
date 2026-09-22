import CloudKit
import Foundation

struct LatestMeme {
    let imageData: Data
    let caption: String
    let senderName: String
    let sentAt: Date
}

enum SharedStore {
    static let appGroupID = "group.com.platteration.widgetwidget"
    static let containerIdentifier = "iCloud.com.platteration.widgetwidget"

    private enum Key {
        static let pairRecordName = "pair.recordName"
        static let pairZoneName = "pair.zoneName"
        static let pairOwnerName = "pair.ownerName"
        static let displayName = "profile.displayName"
        static let latestCaption = "latest.caption"
        static let latestSender = "latest.sender"
        static let latestSentAt = "latest.sentAt"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func savePairRecordID(_ id: CKRecord.ID) {
        defaults.set(id.recordName, forKey: Key.pairRecordName)
        defaults.set(id.zoneID.zoneName, forKey: Key.pairZoneName)
        defaults.set(id.zoneID.ownerName, forKey: Key.pairOwnerName)
    }

    static func pairRecordID() -> CKRecord.ID? {
        guard
            let recordName = defaults.string(forKey: Key.pairRecordName),
            let zoneName = defaults.string(forKey: Key.pairZoneName),
            let ownerName = defaults.string(forKey: Key.pairOwnerName)
        else {
            return nil
        }

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        return CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    static func clearPair() {
        defaults.removeObject(forKey: Key.pairRecordName)
        defaults.removeObject(forKey: Key.pairZoneName)
        defaults.removeObject(forKey: Key.pairOwnerName)
        defaults.removeObject(forKey: Key.latestCaption)
        defaults.removeObject(forKey: Key.latestSender)
        defaults.removeObject(forKey: Key.latestSentAt)
        try? FileManager.default.removeItem(at: latestImageURL)
    }

    static func displayName() -> String {
        defaults.string(forKey: Key.displayName) ?? ""
    }

    static func setDisplayName(_ name: String) {
        defaults.set(name, forKey: Key.displayName)
    }

    static func cacheLatest(_ meme: LatestMeme) {
        try? meme.imageData.write(to: latestImageURL, options: .atomic)
        defaults.set(meme.caption, forKey: Key.latestCaption)
        defaults.set(meme.senderName, forKey: Key.latestSender)
        defaults.set(meme.sentAt.timeIntervalSince1970, forKey: Key.latestSentAt)
    }

    static func cachedLatest() -> LatestMeme? {
        guard let data = try? Data(contentsOf: latestImageURL) else {
            return nil
        }

        let timestamp = defaults.double(forKey: Key.latestSentAt)
        return LatestMeme(
            imageData: data,
            caption: defaults.string(forKey: Key.latestCaption) ?? "",
            senderName: defaults.string(forKey: Key.latestSender) ?? "",
            sentAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : .now
        )
    }

    private static var latestImageURL: URL {
        let baseURL =
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

        return baseURL.appendingPathComponent("latest-meme", conformingTo: .data)
    }
}
