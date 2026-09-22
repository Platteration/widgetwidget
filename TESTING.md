# WidgetWidget two-device validation

Use two physical iPhones signed into different iCloud accounts. Simulator builds verify compilation but do not replace CloudKit sharing and WidgetKit device testing.

## Setup

- Install the same build on Device A and Device B.
- Confirm both devices are signed into iCloud.
- Add the **Shared Meme** widget to both home screens.
- Device A creates the shared widget and sends the private iCloud invitation.
- Device B accepts the invitation.

Expected: Device B automatically becomes connected to the same shared widget, without creating a second pair.

## Send A → B

1. Device A chooses a large screenshot/photo, adds a caption, and sends it.
2. Confirm Device A immediately shows the meme in the app and widget.
3. Leave Device B on the home screen.

Expected:
- The upload succeeds after local image preparation.
- Device B eventually refreshes from the CloudKit change notification / WidgetKit reload request.
- Opening Device B's app and tapping **Refresh** deterministically shows the same meme.
- Sender and caption match.

## Send B → A

Repeat in the opposite direction.

Expected: A participant with read/write share access can create a child `Meme` record and update the shared `Pair` record.

## History and cleanup

Send at least ten memes, alternating devices.

Expected:
- **Recent memes** is ordered newest first.
- At most eight entries remain.
- The current widget meme is always the first history item.
- Sending the ninth and later memes does not break subsequent sends or refreshes.

## Widget sizes and tap-through

Test small, medium, and large widgets.

Expected:
- The image fills the widget without stretching.
- Caption is limited so it does not dominate the widget.
- Sender remains readable against the gradient.
- Tapping any widget opens WidgetWidget.

## Failure cases

- Turn on Airplane Mode and open the widget.
  - Expected: cached latest meme remains visible.
- Attempt to send while offline.
  - Expected: the app reports a CloudKit/network error and keeps the draft available.
- Sign out of iCloud on a test device.
  - Expected: create/send actions report that iCloud is unavailable/not authenticated.
- Reopen the invitation from Device A.
  - Expected: the owner can manage invitations.
- On Device B, confirm the owner-only invite control is not shown.

## Image edge cases

Try:
- portrait screenshot
- landscape image
- very large camera photo
- image with transparency
- very tall meme

Expected: selection remains usable, is bounded before upload, and displays without a crash in all supported widget sizes.

## Refresh timing note

A successful CloudKit push causes the app to request a WidgetKit timeline reload. iOS still controls the actual widget reload budget and timing, so use the in-app **Refresh** action when validating data correctness separately from WidgetKit scheduling behavior.
