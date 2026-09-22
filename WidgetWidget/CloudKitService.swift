import CloudKit
import Foundation
import WidgetKit

struct MemeHistoryItem: Identifiable {
    let id: String
    let meme: LatestMeme
}

@MainActor
final class CloudKitService: ObservableObject {
    private static let historyLimit = 8

    @Published private(set) var pairRecordID: CKRecord.ID?
    @Published private(set) var latest: LatestMeme?
    @Published private(set) var history: [MemeHistoryItem] = []
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var displayName: String

    let container = CKContainer(identifier: SharedStore.containerIdentifier)

    init() {
        pairRecordID = SharedStore.pairRecordID()
        latest = SharedStore.cachedLatest()
        displayName = SharedStore.displayName()

        if let pairRecordID {
            CloudKitPushService.ensureSubscription(for: pairRecordID, container: container)
        }
    }

    var isConnected: Bool {
        pairRecordID != nil
    }

    var isOwner: Bool {
        pairRecordID?.zoneID.ownerName == CKCurrentUserDefaultName
    }

    func persistDisplayName() {
        SharedStore.setDisplayName(displayName.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func reloadFromStore() {
        pairRecordID = SharedStore.pairRecordID()
        latest = SharedStore.cachedLatest()
    }

    func createPair() async -> CKShare? {
        await performBusy {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                throw MemeWidgetError.iCloudUnavailable
            }

            let zoneID = CKRecordZone.ID(
                zoneName: "MemeWidget-\(UUID().uuidString)",
                ownerName: CKCurrentUserDefaultName
            )
            let zone = CKRecordZone(zoneID: zoneID)
            try await saveZone(zone, in: container.privateCloudDatabase)

            let pairID = CKRecord.ID(recordName: "Pair", zoneID: zoneID)
            let pair = CKRecord(recordType: "Pair", recordID: pairID)
            pair["createdAt"] = Date() as CKRecordValue
            pair["title"] = "Meme Widget" as CKRecordValue
            pair["recentMemeRecordNames"] = [] as NSArray

            let share = CKShare(rootRecord: pair)
            share[CKShare.SystemFieldKey.title] = "Meme Widget" as CKRecordValue
            share.publicPermission = .none
            pair["shareRecordName"] = share.recordID.recordName as CKRecordValue

            try await modifyRecords(
                [pair, share],
                in: container.privateCloudDatabase,
                atomically: true
            )

            SharedStore.savePairRecordID(pairID)
            pairRecordID = pairID
            CloudKitPushService.ensureSubscription(for: pairID, container: container)
            WidgetCenter.shared.reloadAllTimelines()
            return share
        }
    }

    func fetchShare() async -> CKShare? {
        await performBusy {
            guard let pairRecordID else {
                throw MemeWidgetError.notConnected
            }
            guard pairRecordID.zoneID.ownerName == CKCurrentUserDefaultName else {
                throw MemeWidgetError.onlyOwnerCanInvite
            }

            let pair = try await container.privateCloudDatabase.record(for: pairRecordID)
            guard let shareRecordName = pair["shareRecordName"] as? String else {
                throw MemeWidgetError.missingShare
            }

            let shareID = CKRecord.ID(
                recordName: shareRecordName,
                zoneID: pairRecordID.zoneID
            )
            guard let share = try await container.privateCloudDatabase.record(for: shareID) as? CKShare else {
                throw MemeWidgetError.missingShare
            }

            return share
        }
    }

    func sendMeme(imageData: Data, caption: String) async -> Bool {
        await performBusy {
            guard let pairRecordID else {
                throw MemeWidgetError.notConnected
            }

            let sender = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sender.isEmpty else {
                throw MemeWidgetError.missingDisplayName
            }
            SharedStore.setDisplayName(sender)

            let database = database(for: pairRecordID)
            let pair = try await database.record(for: pairRecordID)
            let sentAt = Date()

            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("meme-\(UUID().uuidString)", conformingTo: .data)
            try imageData.write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            let memeID = CKRecord.ID(
                recordName: UUID().uuidString,
                zoneID: pairRecordID.zoneID
            )
            let meme = CKRecord(recordType: "Meme", recordID: memeID)
            meme.parent = CKRecord.Reference(recordID: pairRecordID, action: .deleteSelf)
            meme["image"] = CKAsset(fileURL: temporaryURL)
            meme["caption"] = caption.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
            meme["senderName"] = sender as CKRecordValue
            meme["sentAt"] = sentAt as CKRecordValue

            let previousNames = recentRecordNames(from: pair)
            let allNames = [memeID.recordName] + previousNames.filter { $0 != memeID.recordName }
            let keptNames = Array(allNames.prefix(Self.historyLimit))
            let obsoleteIDs = allNames.dropFirst(Self.historyLimit).map {
                CKRecord.ID(recordName: $0, zoneID: pairRecordID.zoneID)
            }

            pair["latestMemeRecordName"] = memeID.recordName as CKRecordValue
            pair["latestSentAt"] = sentAt as CKRecordValue
            pair["recentMemeRecordNames"] = keptNames as NSArray

            try await modifyRecords(
                [meme, pair],
                deleting: obsoleteIDs,
                in: database,
                atomically: true
            )

            let latestMeme = LatestMeme(
                imageData: imageData,
                caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                senderName: sender,
                sentAt: sentAt
            )
            SharedStore.cacheLatest(latestMeme)
            latest = latestMeme
            history = (
                [MemeHistoryItem(id: memeID.recordName, meme: latestMeme)]
                + history.filter { $0.id != memeID.recordName }
            ).prefix(Self.historyLimit).map { $0 }

            WidgetCenter.shared.reloadAllTimelines()
            return true
        } ?? false
    }

    func refreshLatest() async {
        guard let pairRecordID else {
            latest = nil
            history = []
            return
        }

        do {
            let database = database(for: pairRecordID)
            let pair = try await database.record(for: pairRecordID)
            let names = recentRecordNames(from: pair)

            guard !names.isEmpty else {
                latest = nil
                history = []
                return
            }

            let ids = names.prefix(Self.historyLimit).map {
                CKRecord.ID(recordName: $0, zoneID: pairRecordID.zoneID)
            }
            let results = try await database.records(for: ids)

            let loadedHistory = ids.compactMap { id -> MemeHistoryItem? in
                guard
                    case .success(let record)? = results[id],
                    let meme = try? decodeMeme(record)
                else {
                    return nil
                }
                return MemeHistoryItem(id: id.recordName, meme: meme)
            }

            history = loadedHistory
            if let newest = loadedHistory.first?.meme {
                SharedStore.cacheLatest(newest)
                latest = newest
            }
        } catch {
            if latest == nil {
                latest = SharedStore.cachedLatest()
            }
            errorMessage = readable(error)
        }
    }

    func disconnect() {
        SharedStore.clearPair()
        pairRecordID = nil
        latest = nil
        history = []
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func recentRecordNames(from pair: CKRecord) -> [String] {
        if let names = pair["recentMemeRecordNames"] as? [String], !names.isEmpty {
            return names
        }

        if let latestName = pair["latestMemeRecordName"] as? String {
            return [latestName]
        }

        return []
    }

    private func decodeMeme(_ record: CKRecord) throws -> LatestMeme {
        guard
            let asset = record["image"] as? CKAsset,
            let fileURL = asset.fileURL
        else {
            throw MemeWidgetError.missingImage
        }

        return LatestMeme(
            imageData: try Data(contentsOf: fileURL),
            caption: record["caption"] as? String ?? "",
            senderName: record["senderName"] as? String ?? "Friend",
            sentAt: record["sentAt"] as? Date ?? record.creationDate ?? .now
        )
    }

    private func database(for pairRecordID: CKRecord.ID) -> CKDatabase {
        pairRecordID.zoneID.ownerName == CKCurrentUserDefaultName
            ? container.privateCloudDatabase
            : container.sharedCloudDatabase
    }

    private func saveZone(_ zone: CKRecordZone, in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.save(zone) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func modifyRecords(
        _ records: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID] = [],
        in database: CKDatabase,
        atomically: Bool
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(
                recordsToSave: records,
                recordIDsToDelete: recordIDsToDelete
            )
            operation.isAtomic = atomically
            operation.savePolicy = .allKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func performBusy<T>(_ work: () async throws -> T) async -> T? {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            return try await work()
        } catch {
            errorMessage = readable(error)
            return nil
        }
    }

    private func readable(_ error: Error) -> String {
        if let localError = error as? MemeWidgetError {
            return localError.localizedDescription
        }

        if let cloudError = error as? CKError {
            switch cloudError.code {
            case .notAuthenticated:
                return "Sign in to iCloud on this device, then try again."
            case .networkFailure, .networkUnavailable:
                return "CloudKit cannot reach the network right now."
            case .permissionFailure:
                return "This iCloud share does not allow that action."
            default:
                return cloudError.localizedDescription
            }
        }

        return error.localizedDescription
    }
}

enum MemeWidgetError: LocalizedError {
    case iCloudUnavailable
    case notConnected
    case onlyOwnerCanInvite
    case missingShare
    case missingDisplayName
    case missingImage

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is unavailable. Sign in to iCloud and try again."
        case .notConnected:
            return "Create or join a shared meme widget first."
        case .onlyOwnerCanInvite:
            return "Only the person who created this widget can manage its invitations."
        case .missingShare:
            return "The CloudKit share could not be found."
        case .missingDisplayName:
            return "Enter your name before sending a meme."
        case .missingImage:
            return "The latest meme image could not be loaded."
        }
    }
}
