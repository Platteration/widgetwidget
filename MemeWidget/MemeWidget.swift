import CloudKit
import SwiftUI
import UIKit
import WidgetKit

struct MemeEntry: TimelineEntry {
    let date: Date
    let meme: LatestMeme?
}

struct MemeProvider: TimelineProvider {
    func placeholder(in context: Context) -> MemeEntry {
        MemeEntry(date: .now, meme: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (MemeEntry) -> Void) {
        completion(MemeEntry(date: .now, meme: SharedStore.cachedLatest()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemeEntry>) -> Void) {
        Task {
            let cloudMeme = try? await WidgetCloudKitLoader().loadLatest()
            let meme = cloudMeme ?? SharedStore.cachedLatest()

            if let cloudMeme {
                SharedStore.cacheLatest(cloudMeme)
            }

            let entry = MemeEntry(date: .now, meme: meme)
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now)
                ?? .now.addingTimeInterval(15 * 60)

            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

private struct WidgetCloudKitLoader {
    private let container = CKContainer(identifier: SharedStore.containerIdentifier)

    func loadLatest() async throws -> LatestMeme? {
        guard let pairID = SharedStore.pairRecordID() else {
            return nil
        }

        let database = pairID.zoneID.ownerName == CKCurrentUserDefaultName
            ? container.privateCloudDatabase
            : container.sharedCloudDatabase

        let pair = try await database.record(for: pairID)
        guard let latestName = pair["latestMemeRecordName"] as? String else {
            return nil
        }

        let memeID = CKRecord.ID(recordName: latestName, zoneID: pairID.zoneID)
        let meme = try await database.record(for: memeID)

        guard
            let asset = meme["image"] as? CKAsset,
            let fileURL = asset.fileURL
        else {
            return nil
        }

        return LatestMeme(
            imageData: try Data(contentsOf: fileURL),
            caption: meme["caption"] as? String ?? "",
            senderName: meme["senderName"] as? String ?? "Friend",
            sentAt: meme["sentAt"] as? Date ?? meme.creationDate ?? .now
        )
    }
}

struct MemeWidgetEntryView: View {
    let entry: MemeEntry

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if let meme = entry.meme, let image = UIImage(data: meme.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        if !meme.caption.isEmpty {
                            Text(meme.caption)
                                .font(.headline)
                                .lineLimit(2)
                        }

                        Text("from \(meme.senderName)")
                            .font(.caption2)
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title)
                        Text("Send a meme")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(.black, for: .widget)
        .widgetURL(URL(string: "widgetwidget://latest"))
    }
}

struct MemeWidget: Widget {
    let kind = "MemeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MemeProvider()) { entry in
            MemeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Shared Meme")
        .description("Shows the latest meme from your shared WidgetWidget.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct MemeWidgetBundle: WidgetBundle {
    var body: some Widget {
        MemeWidget()
    }
}
