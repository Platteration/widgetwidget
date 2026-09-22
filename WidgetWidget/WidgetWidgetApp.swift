import CloudKit
import SwiftUI
import UIKit
import WidgetKit

extension Notification.Name {
    static let pairDidChange = Notification.Name("pairDidChange")
    static let cloudKitDidChange = Notification.Name("cloudKitDidChange")
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let container = CKContainer(identifier: SharedStore.containerIdentifier)
        let operation = CKAcceptSharesOperation(shareMetadatas: [cloudKitShareMetadata])

        operation.perShareResultBlock = { metadata, result in
            guard case .success = result else { return }

            SharedStore.savePairRecordID(metadata.rootRecordID)
            CloudKitPushService.ensureSubscription(
                for: metadata.rootRecordID,
                container: container
            )
            WidgetCenter.shared.reloadAllTimelines()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pairDidChange, object: nil)
            }
        }

        container.add(operation)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "MemeWidget")
        NotificationCenter.default.post(name: .cloudKitDidChange, object: nil)
        completionHandler(.newData)
    }
}

@main
struct WidgetWidgetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
