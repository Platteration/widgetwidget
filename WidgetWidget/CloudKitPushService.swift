import CloudKit
import Foundation

enum CloudKitPushService {
    static func ensureSubscription(for pairRecordID: CKRecord.ID, container: CKContainer) {
        if pairRecordID.zoneID.ownerName == CKCurrentUserDefaultName {
            let subscriptionID = "pair-zone-\(pairRecordID.zoneID.zoneName)"
            let subscription = CKRecordZoneSubscription(
                zoneID: pairRecordID.zoneID,
                subscriptionID: subscriptionID
            )
            subscription.notificationInfo = silentNotificationInfo()
            ensure(subscription, in: container.privateCloudDatabase)
        } else {
            let subscription = CKDatabaseSubscription(subscriptionID: "shared-database-changes")
            subscription.notificationInfo = silentNotificationInfo()
            ensure(subscription, in: container.sharedCloudDatabase)
        }
    }

    private static func silentNotificationInfo() -> CKSubscription.NotificationInfo {
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        return info
    }

    private static func ensure(_ subscription: CKSubscription, in database: CKDatabase) {
        database.fetchAllSubscriptions { subscriptions, error in
            guard error == nil else {
                return
            }

            let alreadyExists = subscriptions?.contains {
                $0.subscriptionID == subscription.subscriptionID
            } ?? false

            guard !alreadyExists else {
                return
            }

            database.save(subscription) { _, _ in }
        }
    }
}
