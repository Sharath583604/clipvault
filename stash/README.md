# ClipVault

A native iPhone app that keeps a searchable history of clipboard items **you choose to save**,
and lets you paste any earlier item again in two taps. Swift 6, SwiftUI, SwiftData, iOS 17+,
first-party frameworks only. Clipboard content never leaves the device and is never logged.

## Status
| Milestone | State |
|---|---|
| M1 Foundation (ClipKit, tests, targets) | Done |
| M2 MVP (list, search, pin, delete, copy back, PasteButton, hint, Share extension, Settings, Privacy) | Done, see "Not yet verified" |
| M3 Keyboard (recent + pinned, globe key, Full Access detection, secure-field fallback, debug memory readout) | Built, **not run on a device**, see checklist |
| M4 Intents + widget (SaveClipboardIntent, CopyItemIntent, App Shortcuts, small + medium widget, reload after saves) | Built, **not run on a device**, see checklist |
| M5 Polish (Face ID lock, onboarding, empty states, icon placeholder, localization-ready strings, expiry hardening) | Built, **not run on a device**, see checklist |

## Architecture
```
ClipKit (local Swift package, linked by all four targets)
  Models/          ClipItem (@Model, internal) · ClipItemValue (Sendable DTO) · NewClip
  Storage/         ClipStore (actor) · StorageLocation (App Group paths) · ClipSettings · SearchProvider
  Classification/  ContentClassifier (NSDataDetector, OTP, Luhn) · SensitivePolicy
  Ingest/          ProviderIngest (NSItemProvider -> payload) · ImageIngest (ImageIO downsampling)

stash/             App target (product "ClipVault"): AppModel + SwiftUI views
ShareExtension/    Saves text, URLs and images through the share sheet
KeyboardExtension/ SwiftUI keyboard: KeyboardModel (state), KeyboardViews, KeyboardViewController
ClipWidget/        Small and medium widget; each row is a button that copies the clip back
stash/Intents/     ClipEntity, SaveClipboardIntent, CopyItemIntent, App Shortcuts provider
Config/            Info.plists and entitlements for every target
```
- Every process opens its own `ClipStore` on one SQLite file in the App Group
  (`group.com.sclera.clipvault`, `ClipVault/clips.store`); image blobs live in `ClipVault/blobs/`.
- UI and extensions only handle `Sendable` `ClipItemValue`s, never SwiftData models.
- Search goes through the `SearchProvider` protocol (substring today, semantic later).
  Sensitive items are searched by masked preview only.
- The **only** code that reads the pasteboard is a user-tapped `PasteButton`. The foreground
  "new item on clipboard" hint uses `changeCount`, `hasStrings`, `hasURLs`, `hasImages` only.
- Retention applies to items saved after the setting changes. Pinned items never expire
  (except OTP/card items, which always expire after 10 minutes).

## Keyboard design
- **Full Access on:** opens the shared store, shows up to 50 text/link rows (pinned first). Rows hold
  only the preview; the full text is fetched from the store when a row is tapped. Images and files
  are never loaded or decoded. Sensitive items show masked previews but insert their real text.
- **Full Access off:** iOS blocks the shared container, so the store is never opened. The keyboard
  says so in its UI, explains how to enable it, and still offers globe, space, delete and return.
- **Secure fields / phone pad:** iOS swaps in the system keyboard, so ClipVault is not shown there.
  If our keyboard is ever shown while `isSecureTextEntry` is true, history is hidden.
- It never opens the containing app (guideline 4.4.1) and always shows a next-keyboard key.
- Known gaps: no key-repeat on delete, no search inside the keyboard, no haptics (needs Full Access).
- Debug builds show a readout line (Full Access, row count, footprint, bytes free) and a
  `UIPasteControl` probe for device question 3. Neither is compiled into Release.

## Intents and widget design
- **SaveClipboardIntent** (`openAppWhenRun = false`): saves text, a link or an image with capture
  method `intent`. It reads `UIPasteboard` directly unless the optional `content` parameter is
  given. In Shortcuts you can feed it the built-in "Get Clipboard" action's output instead,
  which may avoid any prompt. The result is spoken or shown as a short dialog.
- **CopyItemIntent** (`openAppWhenRun = false`): takes a `ClipEntity` (searchable, with recent
  clips suggested) and writes it back with `PasteboardWriter`. Sensitive items are written
  local-only and expire from the pasteboard after 2 minutes.
- **AppShortcutsProvider** registers both with phrases that include the app name. Either can
  be assigned to the Action button through a Shortcut.
- **Widget** (`systemSmall` and `systemMedium`): always your **two newest** text/link copies,
  newest first (pinning does not reorder them). Sensitive items are never shown, so if your latest
  copy was a one-time code the widget shows the two before it. Each row is
  `Button(intent: CopyClipIntent)`; the tapped row briefly shows a green "Copied" check.
  - Budget: one timeline entry (plus a second entry exactly 5 minutes later that clears the
    "Copied" check, which is the minimum spacing), then no refresh for 30 minutes. Freshness comes
    from `ClipStore`'s `onChange` hook, which calls `WidgetCenter.reloadAllTimelines()` after every
    save, pin, delete, clear and purge in the app, share extension and intents.
  - `CopyClipIntent` lives in `Shared/` and is compiled into **both** the app and the widget
    targets so iOS can run it in the app's process. It is not discoverable in Shortcuts.

## Privacy and polish (M5)
- **Sensitive items:** OTP-like and card-like text is masked everywhere, expires after 10 minutes,
  is excluded from widgets, is copied back local-only (no Universal Clipboard) and lapses from the
  pasteboard after 2 minutes. `ClipStore.item(id:)` refuses expired rows, and any process that
  saves purges expired rows, so a stale keyboard row or shortcut cannot resurrect an old code.
  The open app re-checks every 30 seconds.
- **Face ID lock (optional, Settings → Security):** LocalAuthentication with passcode fallback. It
  locks the **app UI** at launch and on backgrounding, and covers the app-switcher snapshot.
  It deliberately does **not** lock the keyboard, widget, Share extension or Shortcuts. Turning it
  on requires one successful authentication so you cannot lock yourself out.
- **Onboarding:** four pages on first launch (also under Settings → Help and from the empty state)
  covering each capture path and Full Access.
- **Localization:** all user-visible strings use SwiftUI/`String(localized:)`. Each target has a
  `Localizable.xcstrings`; Xcode fills them in when you build in the IDE (File → Export
  Localizations works from the command line). ClipKit has its own catalog and uses `bundle: .module`.
- **App icon:** generated placeholder (default, dark and tinted variants), replace before release.

## Keyboard auto-capture
- With Full Access on, the keyboard saves the clipboard (text and links only; never images, for the
  memory ceiling) when it appears, when the text field changes, and when the system's
  `UIPasteboard.changedNotification` arrives while it is on screen. This is event-driven, not polling.
- **Limit that cannot be engineered away:** iOS keeps one pasteboard item, and nothing of ours runs
  while the keyboard is hidden. If you copy A, B, C in other apps with the keyboard closed, only C is
  saved. Each copy made while the keyboard is visible is saved separately.
- On by default (Settings → Capture, or the switch inside the keyboard). The app and keyboard share
  one "last handled change count" so a copy is never saved twice, and ClipVault's own copy-back
  (app, Shortcut, widget) is not re-captured.
- Reading the contents may raise iOS's paste prompt inside a keyboard; **that is device question 3.**
  The debug line in the keyboard shows `auto-capture: saved a copy` or
  `clipboard not readable (prompt declined?)`.

## Capture timing and speed
- **iOS never reports a copy made in another app**, and apps cannot watch the clipboard in the
  background, so a copy cannot be saved the instant it happens while ClipVault is closed.
- **Opt-in "Save clipboard when ClipVault opens"** (Settings → Capture): reads the clipboard once
  per copy when the app becomes active. iOS shows its paste prompt for this unless you set
  Settings → ClipVault → Paste from Other Apps → **Allow**. Off by default. Capture method is
  recorded as `foregroundRead`.
- **List latency:** a saved item is inserted at the top of the list the moment the store returns,
  then a lighter refresh (no purge) reconciles. Previously the list only refreshed on a 30-second
  timer or scene change, so new items could take up to 30 seconds to appear.

## How to enable the keyboard
Settings → General → Keyboard → Keyboards → Add New Keyboard… → ClipVault, then tap ClipVault
and turn on **Allow Full Access** to show your history. In any text field, long-press or tap the
globe key to switch to ClipVault.

## Run it
1. Open `stash.xcodeproj`, select the **stash** scheme.
2. Signing & Capabilities: choose your team for **all four targets**. The App Group
   `group.com.sclera.clipvault` must be registered to that team; if it is taken, rename it in
   `Config/*.entitlements` and `StorageLocation.appGroupIdentifier` (ClipKit/.../AppGroup.swift).
3. Run on a device (the simulator hides signing and keyboard-memory problems).

Command line (simulator, ad-hoc signed so the App Group entitlement is embedded):
```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project stash.xcodeproj -scheme stash -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO
(cd ClipKit && swift test)
```

## Tests
`ClipKit` has 53 Swift Testing tests: add, dedupe, search, pin, expiry/purge, classifier,
sensitive policy, image ingest, settings, app lock state machine, expiry hardening, keyboard and widget queries (text-only, 50-row cap, pinned first, no sensitive in widgets), the change hook, and a two-store cross-process simulation (two
`ModelContainer`s on one SQLite file, including concurrent writers). There is no app UI test
target yet; every view has an Xcode preview.

## Manual test checklist (not verified by automated tests)
Mark each with the device, iOS version and result.

### M2, main app and Share extension
- [ ] Tap Paste in the toolbar with text on the clipboard: item saved, **no** system paste alert.
- [ ] Same with a URL and with an image.
- [ ] Copy text in another app, return to ClipVault: the "New item on clipboard" banner appears.
      Reading `changeCount`/`hasStrings`/`hasURLs`/`hasImages` shows **no** paste alert. (Device question 1.)
- [ ] After saving or dismissing, the banner does not reappear until the clipboard changes.
- [ ] Tap a row: item is written back, "Copied" is announced; paste it elsewhere.
- [ ] Copy-back of an OTP does not appear on a second device via Universal Clipboard.
- [ ] Swipe right to pin, left to delete; VoiceOver rotor actions "Pin" and "Delete" work.
- [ ] Search is case-insensitive; an OTP cannot be found by its digits.
- [ ] Share from Safari (URL), Notes (text), Photos (image): all save; image row shows a thumbnail.
- [ ] Share a very large photo: the extension does not get killed (memory).
- [ ] Settings: retention picker, Clear all history, Privacy policy screen.
- [ ] Dynamic Type at the largest accessibility size: rows, banner, and settings stay usable.
- [ ] VoiceOver reads each row as "<kind>, <preview>, Pinned" with a "Double tap to copy" hint.

### M3, keyboard (device only)
- [ ] Add the keyboard; switch to it with the globe key, and back again.
- [ ] Full Access **off**: explanation is shown, space/delete/return work, globe works, no crash.
- [ ] Full Access **on**: pinned items first, then recent; tap inserts the full text at the cursor.
- [ ] Items saved in the app or Share sheet appear after reopening the keyboard.
- [ ] Image clips never appear in the keyboard.
- [ ] Focus a password field and a phone-pad field: system keyboard takes over, no crash.
- [ ] Keyboard height and the key bar look right on small and large iPhones, light and dark mode.
- [ ] VoiceOver reads rows and keys; largest Dynamic Type stays usable.
- [ ] Memory: see below.

### M4, intents and widget (device only)
- [ ] Shortcuts app: both ClipVault actions and both App Shortcuts are listed.
- [ ] Run "Save Clipboard to ClipVault" from Shortcuts with text, a link and an image copied.
- [ ] Same with a Shortcut that passes "Get Clipboard" into the `Content` parameter.
- [ ] Assign the Shortcut to the Action button and press it; item is saved without opening the app.
- [ ] "Copy a clip from ClipVault" (also via Siri): picks a clip, then pasting elsewhere inserts it.
- [ ] Add the small and medium widgets. Rows show recent clips; OTP/card items are absent.
- [ ] Tap a widget row, then paste in another app: the clip is inserted. **If the write does not
      stick when the widget extension runs the intent, the fix is to run that intent in the app
      process; note it here.**
- [ ] Save in the app or Share sheet: the widget updates within a few seconds.
- [ ] Widget with no clips, and before the app was ever opened, shows the empty/setup message.
- [ ] Widget text is readable in light, dark and Tinted modes.

### M5, polish (device only)
- [ ] Settings → Require Face ID: prompts once, then locks on background and on relaunch.
- [ ] Locked app: cover hides content in the app switcher; Unlock works; cancelling stays locked.
- [ ] Device without Face ID/passcode: toggle is disabled with an explanation.
- [ ] Keyboard, widget and Shortcuts still work while the app is locked (expected).
- [ ] Save a 6-digit code: masked in the list, absent from the widget, gone from the keyboard and
      app after ~10 minutes.
- [ ] Copy an OTP back, wait 2 minutes: pasting no longer inserts it.
- [ ] First launch shows the intro; Skip and Get started both dismiss it and it does not return.
- [ ] Settings → Help reopens it. Empty-state "How ClipVault works" opens it.
- [ ] Icon looks right in light, dark and tinted Home Screen modes.
- [ ] Pseudolanguage run (Scheme → Options → Application Language: Double-Length) shows no clipped
      or untranslated text.

### Capture, list speed and widget (device only)
- [ ] Paste via the button: the item appears at the top of the list immediately, with no visible delay.
- [ ] Paste an image: the row appears right after saving (thumbnail may follow a moment later).
- [ ] With "Save clipboard when ClipVault opens" ON and Paste from Other Apps = Ask: copy in another
      app, open ClipVault, see the iOS prompt; Allow saves it, Don't Allow does not re-ask until you copy again.
- [ ] Same with Paste from Other Apps = **Allow**: no prompt, item saved on open.
- [ ] Widget (small and medium) shows exactly your two newest copies; copy something new in the app,
      the widget updates within a few seconds.
- [ ] Tap a widget row: the row shows "Copied" with a green check, then pasting elsewhere inserts it.
      **If the check appears but pasting inserts the old clipboard, the write is not sticking when the
      intent runs; tell me which process ran it.** If nothing happens at all, the intent is not running.
- [ ] The check disappears after about 5 minutes.

### Keyboard auto-capture (device only, Full Access on)
- [ ] Copy text in Safari/Notes, open a text field, switch to ClipVault: the copy appears at the top.
      Note whether an iOS paste prompt appeared and whether the debug line says "saved a copy".
- [ ] Copy a link: saved as a link row.
- [ ] With the keyboard still showing, select and copy two different pieces of text one after the
      other: both are saved (this is the notification path).
- [ ] Copy A, B, C with the keyboard closed, then open it: only C is saved (expected iOS limit).
- [ ] Copy an image: nothing is saved by the keyboard and nothing crashes.
- [ ] Switch the keyboard's "Save my copies automatically" off: nothing more is saved; the app's
      Settings toggle shows the same state.
- [ ] Copy-back from the app or widget does not create a duplicate or reorder the list oddly.
- [ ] Watch memory in the debug line while it captures a very large copied text.

### Share sheet and clipboard (device only)
- [ ] Copy "OLD", then share "NEW" to ClipVault from another app. The sheet says "Saved and copied".
      Pasting anywhere gives **NEW**, not OLD.
- [ ] Open the ClipVault keyboard right after: it does **not** re-save OLD on top of NEW (the shared
      "last handled" marker was updated by the share).
- [ ] Share a link and a photo: pasting gives the link / the image.
- [ ] Settings → "Copy shared items to the clipboard" OFF: sharing only saves; the clipboard is untouched.

### Device questions (to answer on real hardware)
| # | Question | Result |
|---|---|---|
| 1 | Does reading `pasteboard.changeCount` show a paste alert? | _pending_ |
| 2 | Does an App Intent that reads the clipboard prompt, from the Action button and from a Shortcut? (Test `SaveClipboardIntent` with `Content` empty, then with Get Clipboard passed in) | _pending_ |
| 3 | Does `UIPasteControl` work inside the keyboard extension? (Debug build: tap the paste icon above the key bar; the readout shows what it delivered and whether an alert appeared) | _pending_ |
| 4 | Keyboard behavior and memory, Full Access off and on | _pending_ |

### Keyboard memory test
Use the Debug readout (footprint and bytes free) and Instruments > Allocations on the keyboard
process. Record for each case: Full Access off; on with 0 rows; on with 50 short rows; on with 50
rows of ~100,000 characters (worst case); after switching apps ten times. Target: well under 60 MB.
The ceiling varies by device and iOS version, so also note the model and OS.

| Case | Device / iOS | Footprint | Free |
|---|---|---|---|
| Full Access off | | | |
| On, 0 rows | | | |
| On, 50 short rows | | | |
| On, 50 huge rows | | | |
| After 10 app switches | | | |
