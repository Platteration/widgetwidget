import CloudKit
import SwiftUI
import UIKit
import WidgetKit

extension Notification.Name {
    static let pairDidChange = Notification.Name("pairDidChange")
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let container = CKContainer(identifier: SharedStore.containerIdentifier)
        let operation = CKAcceptSharesOperation(shareMetadatas: [cloudKitShareMetadata])

        operation.perShareResultBlock = { metadata, result in
            guard case .success = result else { return }

            SharedStore.savePairRecordID(metadata.rootRecordID)
            WidgetCenter.shared.reloadAllTimelines()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pairDidChange, object: nil)
            }
        }

        container.add(operation)
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
