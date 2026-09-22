# WidgetWidget

WidgetWidget is an iOS app plus WidgetKit extension for a shared home-screen meme widget.

One friend creates a private CloudKit record zone and invites another person through Apple's iCloud sharing sheet. Either participant can then choose an image, add an optional caption, and make it the latest meme shown on both devices' widgets.

## What is implemented

- Native SwiftUI app for iOS 17+
- WidgetKit home-screen widget in small, medium, and large sizes
- Two-person-or-more sharing through `CKShare`
- Read/write CloudKit sharing with no custom backend
- Meme image stored as a `CKAsset`
- Shared root record points directly to the current meme, so the widget does not need a CloudKit query/index
- Local App Group cache for offline/failure fallback
- Manual refresh plus WidgetKit timeline refresh
- Creator can reopen the iCloud invitation sheet
- Participant accepts the standard iCloud share link and is connected automatically

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project file does not need to be committed.

```bash
brew install xcodegen
xcodegen generate
open WidgetWidget.xcodeproj
```

## Apple Developer setup

The project currently uses these identifiers:

- App bundle: `com.platteration.widgetwidget`
- Widget bundle: `com.platteration.widgetwidget.MemeWidget`
- App Group: `group.com.platteration.widgetwidget`
- iCloud container: `iCloud.com.platteration.widgetwidget`

Before running on devices:

1. Select your Apple Developer team for both targets in Xcode.
2. Create/enable the App Group above for both targets.
3. Create/enable the iCloud container above with CloudKit for both targets.
4. Confirm the main app has CloudKit Sharing enabled.
5. Run once against the CloudKit **Development** environment so the `Pair` and `Meme` record types/fields are created.
6. Before TestFlight/App Store distribution, deploy the development schema to **Production** in CloudKit Dashboard.

If your Developer account uses different identifiers, update `project.yml`, both entitlement files, and the constants in `Shared/SharedStore.swift`.

## Test on two devices

Both devices should be signed in to iCloud.

1. Device A: launch WidgetWidget, enter a name, and tap **Create Shared Widget**.
2. Device A: invite Device B from the iCloud sharing sheet with read/write access.
3. Device B: open the invitation link and accept the CloudKit share.
4. On both devices, add **Shared Meme** from the iOS widget gallery.
5. Either device: pick an image and tap **Send to Widget**.
6. Use **Refresh** in the app if you want to verify immediately. WidgetKit also asks CloudKit for the latest meme on its timeline refresh.

## Architecture

```
WidgetWidget app
  ├─ creates private custom CKRecordZone
  ├─ Pair root record + CKShare
  ├─ writes Meme records as CKAsset images
  └─ updates Pair.latestMemeRecordName atomically

Friend accepts CKShare
  └─ same zone appears in sharedCloudDatabase

MemeWidget extension
  ├─ reads pair record ID from shared App Group
  ├─ chooses privateCloudDatabase (owner) or sharedCloudDatabase (friend)
  ├─ fetches Pair, then the exact latest Meme record
  └─ falls back to the App Group cache if CloudKit is unavailable
```

## Current MVP limits

- Images are displayed as static images; animated GIF playback and video are not implemented.
- Widget refresh timing is ultimately controlled/throttled by iOS. Sending from the local device explicitly reloads WidgetKit; a remote friend's change appears on the recipient widget when WidgetKit next grants a refresh.
- The app currently maintains one connected shared widget per device.
- Disconnecting removes the local connection only. The share owner manages participants from the iCloud sharing sheet.
- There is no moderation/reporting layer; only invite people you trust.

## Next useful upgrades

Push-driven refresh, reactions, a small meme history, multiple friend groups/widgets, deep links from the widget back to the thread, and basic image compression before CloudKit upload are natural follow-ups.
