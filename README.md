

# ClipVault: The Complete Guide

A plain-language explanation of what ClipVault is, how it is built, why it is built that way, and
what each part is for. No prior iOS knowledge needed.

> **Honesty note.** Everything described here compiles and the logic in the shared code is
> covered by 53 automated tests. Almost nothing has been run on a real iPhone yet. Sections
> say "Not yet verified" wherever that matters, and the list of things to try on a device is at
> the end.

---

## 1. What is ClipVault?

Your iPhone's clipboard remembers **one** thing at a time. Copy something new and the old thing is gone.

**ClipVault is a notebook for your clipboard.** It keeps a history of things you copied, lets you
search it, pin the important ones, and paste any earlier item again in two taps. It works in four places:

| Where | What you do there |
|---|---|
| **The app** | See your history, search, pin, delete, tap to copy back |
| **The share sheet** | From any app: Share → "Save to ClipVault" |
| **The keyboard** | While typing anywhere, tap an old item to insert it |
| **The widget** | On your Home Screen: tap one of your two latest copies to copy it |

Everything stays **on your phone**. No server, no account, no analytics.

**Typical use cases**
- You copied a tracking number, then copied an address, and need the tracking number again.
- You keep re-typing the same email, address or snippet: pin it and insert it from the keyboard.
- You copy a link in Safari and want it available from the Home Screen widget later.
- A one-time code arrives: ClipVault hides it and deletes it after 10 minutes.

---

## 2. The big problem: iOS protects the clipboard

The most important thing to understand is that **iOS deliberately limits what apps can do with the
clipboard.** The whole design of ClipVault is a response to these rules.

| iOS rule | What it means | What ClipVault does about it |
|---|---|---|
| **No background clipboard watching.** An app cannot be told "the user just copied something." | ClipVault can never silently record everything you copy. | It saves things only when you act (paste button, share sheet, Shortcut) or when its app/keyboard is open. It never loops or polls in the background. |
| **Reading the clipboard shows a "Allow Paste" alert** (iOS 16+), unless the user taps a special system Paste button. | A normal read interrupts you. | The main way to save is the system **Paste button**, which is allowed to read without an alert. |
| **Keyboards are sandboxed.** A keyboard has no internet and cannot see the app's data unless the user turns on **Allow Full Access**. | Without Full Access the keyboard cannot show your history. | The keyboard works in a reduced form (space, delete, return, globe key) and *tells the user why*. |
| **Keyboards must not open their app** (App Review rule 4.4.1) and must offer a way to switch keyboards. | No shortcuts back into the app. | The keyboard never launches the app and always has a globe key. |
| **Secure fields (passwords) and phone-pad fields** use the system keyboard. | A custom keyboard never appears there. | Nothing to do, but if it ever appears in a secure field it hides history. |
| **Keyboards have a small memory budget** (~60 MB, varies). | Loading a lot of data can get the keyboard killed. | Text only, at most 50 rows, never decodes images, loads full text only when you tap a row. |
| **Widgets get a limited refresh budget.** | A widget cannot refresh constantly. | Very few timeline entries (at least 5 minutes apart); the app asks the widget to reload after each save. |

**Key takeaway:** "automatically save every copy" is **not possible** on iOS. What *is* possible is
saving at the right moments. Sections 6–7 explain exactly which moments.

---

## 3. The big picture

ClipVault is **four programs plus one shared "brain"**, all sharing one database file.

```
        ┌────────┐   ┌───────────────┐   ┌──────────────┐   ┌────────────┐
        │  App   │   │ Share sheet   │   │  Keyboard    │   │  Widget    │
        │ (main) │   │  extension    │   │  extension   │   │ extension  │
        └───┬────┘   └──────┬────────┘   └──────┬───────┘   └─────┬──────┘
            │               │                   │                 │
            └───────────────┴─────────┬─────────┴─────────────────┘
                                      ▼
                         ┌─────────────────────────┐
                         │  ClipKit  (shared code)   │   the "brain"
                         │  store · rules · helpers  │
                         └────────────┬─────────────┘
                                      ▼
                      ┌────────────────────────────────┐
                      │ Shared folder ("App Group")      │
                      │  clips.store  (the database)     │
                      │  blobs/       (saved images)     │
                      │  settings (small preferences)    │
                      └────────────────────────────────┘
```

### Concept: App Extension
An **extension** is a small separate program that lives inside your app and plugs into iOS: the
share sheet, a keyboard, a widget. Each runs in its **own process** with its own memory and rules.
They do not share variables with the main app; they can only share **files**.

### Concept: App Group (the shared folder)
Because the app, keyboard, share sheet and widget are separate programs, they need somewhere to
meet. An **App Group** is a folder iOS lets several of your programs share. ClipVault puts its
database and settings there. This is why every target needs the same App Group entitlement and
why signing errors about "App Group not available" matter: without it, each program would see its own
empty database.

### Concept: ClipKit (a Swift package)
Instead of copying the same code into four places, the shared logic lives in **ClipKit**, a
separate local library that all four targets link. Fix a bug once, all four benefit. ClipKit also
has automated tests that run quickly on a Mac without an iPhone.

---

## 4. Concepts used, explained simply

| Concept | Plain-English meaning | Where it appears |
|---|---|---|
| **SwiftUI** | Apple's way of describing screens as code ("a list of rows, each with text") | All screens |
| **SwiftData** | Apple's built-in database. Saves objects to a file (SQLite) | `ClipStore` |
| **Actor** | A safe "single-file line" for code: only one task touches the data at a time. Prevents corruption when many things run at once | `ClipStore` is an actor |
| **Sendable / DTO** | A plain copy of data that is safe to hand between threads. The database objects themselves are not handed around; copies (`ClipItemValue`) are | `ClipItemValue` |
| **Swift 6 strict concurrency** | The compiler checks for data-race bugs. Turned on everywhere | All targets |
| **PasteButton** | A system-provided button. When *you* tap it, iOS lets the app read the clipboard once without an alert | Main app |
| **`changeCount`** | A number that goes up every time the clipboard changes. Checking it does not read the contents, so it never triggers the alert | Hint banner, keyboard |
| **NSDataDetector** | Apple's text scanner that recognises links, emails, phones, addresses, dates | `ContentClassifier` |
| **Luhn check** | The math every real credit-card number passes. Used to guess "this looks like a card" | `ContentClassifier` |
| **App Intents** | Lets Shortcuts, Siri, the Action button and widget buttons run small pieces of your app | `Intents/`, `Shared/` |
| **WidgetKit timeline** | A widget is not a running program; you hand iOS a list of "what to show at what time" | `ClipWidget` |
| **Full Access** | A keyboard setting that lets it use the shared folder (and the network, in general) | Keyboard |
| **Entitlement** | A permission stamped into the app by Apple at signing time (e.g. "may use this App Group") | `Config/*.entitlements` |
| **LocalAuthentication** | Face ID / Touch ID / passcode prompts | App lock |
| **String catalog** | A file where all on-screen text lives so it can be translated later | `Localizable.xcstrings` |

---

## 5. ClipKit: the shared brain, file by file

### Data
- **`ClipItem`** (internal): one saved clip in the database. Fields: id, createdAt, kind
  (text / url / image / file), text, preview, blobPath, contentHash, isPinned, expiresAt,
  isSensitive, captureMethod.
- **`ClipItemValue`**: a plain, safe copy of a `ClipItem` for screens to use. Has a helper
  `strippingText()` that removes the full text and keeps only the short preview (used by the keyboard).
- **`NewClip`**: the "please save this" request given to the store.
- **`captureMethod`** records how it arrived: `pasteButton`, `share`, `intent`, `keyboard`, or
  `foregroundRead` (auto-saved when the app opened).

### The store: `ClipStore`
The only door to the database. Every program opens its own `ClipStore` on the same file.

| Function | What it does | Why |
|---|---|---|
| `add` | Saves a clip. If the same content (by fingerprint/hash) already exists, it does **not** duplicate it; it moves the old one to the top | No clutter from copying the same thing twice |
| `ingest` | Takes a pasted/shared thing (text, URL, image), prepares it, calls `add`. Images are shrunk to max 2048 px and stored as files | One path for every capture method |
| `search` | Case-insensitive "contains" search | Find old clips fast. Written behind a `SearchProvider` interface so smarter semantic search can be plugged in later |
| `recent`, `pinned` | Newest first / pinned only | Main list |
| `keyboardItems` | Up to 50 text/link rows, pinned first, short previews only | Keeps keyboard memory small |
| `widgetItems` | The newest **2** text/link clips, never sensitive | Widget content |
| `item(id:)` | Fetches one clip with full text; returns nothing if it has expired | Used when you tap something |
| `pin`, `delete`, `deleteAll` | Obvious | Also remove image files |
| `purgeExpired` | Deletes expired rows | Also runs automatically whenever anything is saved |
| `onChange` hook | Called after every write so widgets reload | Keeps widget fresh without polling |

### Rules and detection
- **`ContentClassifier`**: looks at text and decides what it is: link, email, phone, address, date,
  **OTP-like** (4–8 digits, short), **card-like** (13–19 digits that pass the Luhn check).
- **`SensitivePolicy`**: OTP and card items are **masked** ("••••••", "•••• •••• •••• 4242") and
  **expire after 10 minutes**. Normal items expire after your "keep for N days" setting
  (0 = forever). Pinned normal items never expire.

### Capturing and writing helpers
- **`ProviderIngest`**: turns what the system hands over (from the Paste button or share sheet) into
  text / URL / image data. Preference order: URL, then text, then image.
- **`ImageIngest`**: shrinks images safely using Apple's ImageIO so a large photo cannot blow up memory.
- **`PasteboardWriter`**: puts a clip back on the system clipboard. Sensitive items are written
  **local-only** (no Universal Clipboard to your other devices) and **expire from the clipboard after 2 minutes**.
  It also records "I did this" so ClipVault doesn't re-save its own copy-back.

### Settings and security
- **`ClipSettings`**: small preferences stored in the shared folder: retention days, Face ID lock,
  auto-save on open, keyboard auto-save, and the "last handled clipboard change number" shared by
  app and keyboard.
- **`AppLock`**: the Face ID logic as a small state machine (locked / unlocked / authenticating),
  written so it can be tested with a fake authenticator.
- **`StorageLocation`**: finds the shared folder (or a temp folder in tests).
- **`WidgetCopyState`**: remembers "this row was just tapped" so the widget can show "Copied ✓".
- **`WidgetRefresh`**: one line that tells WidgetKit "reload now".
- **`MemoryFootprint`**: reads how much memory the process uses (debug aid for the keyboard).
- **`ContentHash`**: SHA-256 fingerprint used for duplicate detection.

---

## 6. Features: what, how, why, use case

### 6.1 Saving clips (five ways)

| Way | How it works | Why this way | Use case |
|---|---|---|---|
| **Paste button** | Tap the paste icon in the app. iOS lets that button read the clipboard once, no alert | The only alert-free in-app read | Copy something anywhere, open ClipVault, tap paste |
| **Share sheet** | Share → "Save to ClipVault". Content arrives directly, so ClipVault never has to *read* the clipboard. By default it then also *writes* the shared item to the clipboard so your next paste gives it (Settings → "Copy shared items to the clipboard") | No clipboard permission needed; writing never raises an alert | Save a link from Safari, text from Notes, a photo |
| **Shortcut / Action button** | `SaveClipboardIntent` runs without opening the app | One-press capture | Press the Action button after copying |
| **Save when app opens** (optional, off by default) | When ClipVault becomes active it reads the clipboard once per copy | Closest iOS allows to "automatic" | Copy something, open ClipVault, it's already there |
| **Keyboard auto-capture** (on by default, needs Full Access) | The keyboard saves the clipboard when it appears and when the system says the clipboard changed while it's visible | Lets you capture several copies in a row while typing | Copy in one place, switch to ClipVault keyboard, see it saved |

**Why not "always automatic"?** iOS offers no way for an app to be told about a copy. If you copy
A, B and C in other apps while no ClipVault part is running, **only C can ever be saved.** This is
an iOS limit, not a bug.

The **"new item on clipboard" banner** in the app uses only `changeCount`, `hasStrings`, `hasURLs`,
which do not read the clipboard, so showing it never triggers an alert.

### 6.2 The main list
- Search bar, **Pinned** section, **Recent** section.
- Swipe right to pin/unpin, swipe left to delete, tap a row to **copy it back**.
- Image rows show small thumbnails (decoded off the main thread).
- After you paste/save, the new item is **inserted instantly** at the top, then a light refresh
  confirms it. (Earlier it only refreshed every 30 seconds. That was a bug, now fixed.)
- A background timer refreshes every 30 seconds while the app is open so expired codes disappear.
- Empty state with a "How ClipVault works" button; separate "no search results" state.

### 6.3 Sensitive items (codes and card numbers)
1. Saved text is scanned. 4–8 digits in short text → "OTP-like". 13–19 digits passing Luhn → "card-like".
2. Marked sensitive: **masked preview**, **10-minute expiry**, **excluded from the widget**,
   **not searchable by their digits**, copied back **local-only** and gone from the clipboard after 2 minutes.
3. Even stale screens cannot resurrect them: expired items cannot be fetched, and any save purges expired rows.

### 6.4 The keyboard
- Rows: pinned first, then recent, text and links only, max 50, short previews only.
- Tap a row → the **full text is fetched at that moment** and inserted at the cursor.
- Bottom bar: globe (next keyboard), space, delete, return. Always present, even without Full Access.
- **Full Access off:** it never touches the shared folder; it explains what Full Access is and how to
  enable it (Settings → General → Keyboard → Keyboards → ClipVault → Allow Full Access).
- **Secure field:** history hidden if ever shown.
- **Auto-capture** (see 6.1) plus a slim switch, "Save my copies automatically".
- **Debug build only:** a readout line (Full Access, rows, memory used/free) and a tiny paste-control
  test for checking an iOS behavior on a real device.

### 6.5 The widget
- Small and medium sizes, always the **two newest** copies (pinning doesn't reorder them), taller rows.
- **Tap a row to copy it**; the row flips to a green "Copied" check for about 5 minutes.
- Never shows sensitive items (widgets can be seen on the Lock Screen).
- Refresh plan: one entry now, a second entry exactly 5 minutes later (clears the check), then no
  refresh for 30 minutes. Freshness comes from the app/extension asking for a reload after each save.
- The tap handler (`CopyClipIntent`) is compiled into both the app and the widget so iOS can run it
  inside the app's process, which should be more reliable for writing the clipboard.
  **Not yet verified on a device.**

### 6.6 Shortcuts, Siri and the Action button
- **Save Clipboard to ClipVault**: optional "Content" input. If a Shortcut passes in "Get Clipboard",
  the intent uses that instead of reading the clipboard itself (may avoid any prompt).
- **Copy Clip from ClipVault**: pick a clip (searchable, recent ones suggested) and put it on the clipboard.
- Both are registered as App Shortcuts with spoken phrases, so they appear in the Shortcuts app and can be assigned to the Action button.

### 6.7 Settings and privacy screens
- Keep clips for 1 / 7 / 30 / 90 days / forever (applies to newly saved clips).
- Capture toggles: save when app opens; save when keyboard opens; button to jump to iOS Settings.
- Require Face ID. Clear all history. Privacy policy. "How ClipVault works". Version.

### 6.8 Face ID lock (optional)
Locks the **app screens** when the app opens or comes back from the background, and covers the
app-switcher preview. To turn it on you must authenticate once (so you can't lock yourself out).
It deliberately does **not** lock the keyboard, widget, share sheet or Shortcuts, because those exist
to work without opening the app. Settings says so.

### 6.9 Onboarding
Four pages on first launch, also available in Settings: what ClipVault is and the clipboard limits,
the ways to save, the keyboard and Full Access (honestly explained), and privacy. Mentions that
copies made while ClipVault isn't running can't be captured.

### 6.10 Localization and icon
- Every on-screen string is translation-ready. Each target has a string catalog, ClipKit has its own,
  and a test export extracted 141 strings. No translations exist yet; English only.
- App icon is a generated **placeholder** (light, dark, tinted). Replace before release.

---

## 7. Walk-throughs: what happens step by step

**A. You copy a link in Safari and tap the paste button in ClipVault**
1. Paste button → iOS hands over the clipboard item (no alert).
2. `ProviderIngest` turns it into "URL payload".
3. `ClipStore.ingest` → `add`: fingerprint it, check for duplicate, classify it (single link → kind "url"),
   set expiry, save.
4. The row appears at the top instantly; the widget is told to reload.

**B. You type in Notes with the ClipVault keyboard (Full Access on)**
1. Keyboard appears → checks `changeCount`. Changed since last time? → reads the clipboard
   (iOS may prompt; unverified) → saves it → marks that change as handled.
2. The list reloads; the new item is at the top. Tap an old row → full text fetched → inserted at the cursor.

**C. A 6-digit code is copied and saved**
Classified OTP → masked "••••••" → expires in 10 min → hidden from the widget → when copied back it is
local-only and vanishes from the clipboard in 2 minutes → after 10 minutes it can't be fetched anywhere.

**D. You tap a widget row**
`CopyClipIntent` runs → loads full text from the store → writes the clipboard → records "copied" → widget
reloads and shows ✓ Copied for ~5 minutes.

---

## 8. Where everything lives

```
stash.xcodeproj           the Xcode project (4 targets + ClipKit package)
ClipKit/                  shared brain + 53 tests
  Sources/ClipKit/        Models · Storage · Classification · Ingest · Security · Util · Resources
  Tests/ClipKitTests/
stash/                    MAIN APP (product name "ClipVault")
  stashApp.swift          app entry
  RootView.swift          lock cover + first-run onboarding
  AppModel.swift          app logic + the ONLY pasteboard reads in the app
  ClipListView.swift      main screen        ClipRowView.swift   one row + thumbnails
  ClipboardHintBanner     "new item" banner  EmptyStateView      empty state
  SettingsView            settings           PrivacyPolicyView   policy text
  OnboardingView          intro pages        PreviewSupport      sample data for previews
  Intents/                Save / Copy intents, ClipEntity, App Shortcuts
ShareExtension/           share sheet "Save to ClipVault"
KeyboardExtension/        KeyboardViewController (UIKit host) · KeyboardModel (state) · KeyboardViews
ClipWidget/               widget + timeline
Shared/                   CopyClipIntent (compiled into app AND widget)
Config/                   Info.plists + entitlements (App Group)
docs/                     this guide
README.md                 quick reference + device checklist
```

Why the app folder is named `stash`: the Xcode project you created was named "stash". The built app is
still called **ClipVault** (display name and product name).

---

## 9. Build, run, and set up

1. Open `stash.xcodeproj`, scheme **stash**.
2. For all four targets: Signing & Capabilities → pick your team.
3. The **App Group** name must be unique on Apple's side. `group.com.stash` was taken, so the code
   was changed to `group.com.sclera.clipvault`; your bundle IDs are `com.shar.clipvault…`.
   **If you register a different group name, change it in all four `Config/*.entitlements` files and in
   `StorageLocation.appGroupIdentifier`.** Bundle IDs of the extensions must start with the app's bundle ID.
4. Run on a real iPhone (iOS 17+). The simulator hides signing/Full Access/memory problems.
5. Add the keyboard: Settings → General → Keyboard → Keyboards → Add New Keyboard → ClipVault, then tap it
   and turn on **Allow Full Access**.
6. Optional: Settings → ClipVault → *Paste from Other Apps* → **Allow** removes iOS's paste prompts.

Command line (simulator test build) and tests are in the README.

---

## 10. Testing: what is and isn't covered

**Covered by 53 automated tests (ClipKit):** adding, duplicate handling, search, pin, expiry/purge, expired
items not fetchable, classifier (links, email, phone, date, address, OTP, card/Luhn), masking, retention,
image shrinking and cleanup, settings, the Face ID state machine (with a fake), keyboard/widget queries
(text-only, 50-row cap, pinned-first for keyboard, newest-two for widget, no sensitive in widget),
change-notification hook, and **two separate stores reading one database file** (a stand-in for app + keyboard).

**Not covered by tests (needs a real phone):** all SwiftUI screens (they have Xcode previews), the share
extension, the keyboard, the widget, App Intents, Face ID prompts, the real two-process behavior.

**Build checks done:** Debug and Release build cleanly for all four targets with Swift 6 strict concurrency;
the app launches in the simulator and shows onboarding; the intents and shortcuts appear in the built app's
metadata; the localization export finds the strings.

---

## 11. Known limits (by design, not bugs)

- Copies made while no ClipVault part is running are lost, except the very latest one.
- The keyboard can only show history with **Full Access**.
- The keyboard never saves images (memory).
- Face ID lock covers the app only.
- Retention days apply to clips saved after you change the setting.
- No delete key-repeat, no in-keyboard search, no haptics in the keyboard.
- Only English text; no semantic search yet.

---

## 12. Decisions and changes made along the way

| What | Why |
|---|---|
| Built ClipKit first and tested it on a Mac | Most logic is platform-independent and needs fast feedback |
| Generated the Xcode project file by script (no extra tools) | Extra tools needed approval; hand-editing is fragile |
| Renamed App Group and bundle IDs | Apple said the first names were already taken |
| Added "save when app opens" and keyboard auto-capture | You asked for more automatic capture. This relaxes the original "only via paste button/share/intent" rule, so both are clearly explained and switchable, and the privacy text was updated to match |
| Fixed the delay after pasting | List wasn't refreshed after saving; now inserts immediately |
| Moved the widget's tap action into both app and widget | More reliable place to write the clipboard (to be verified) |
| Widget changed from 3–4 rows to exactly 2, newest first | You asked for the two most recent copies |
| Used a few first-party frameworks not on your original list | CryptoKit (hashing), ImageIO (image shrinking), LocalAuthentication (Face ID), UniformTypeIdentifiers. All Apple, no third-party packages |

---

## 13. What to test on your phone (short version)

The README has the full checklist. The most important five:

1. **Does reading the clipboard from the keyboard show iOS's paste prompt?** (decides whether auto-capture feels good)
2. **Does tapping a widget row really copy?** (the "Copied ✓" tells you whether the tap ran; pasting tells you whether it stuck)
3. **Does the keyboard stay under the memory limit** with Full Access on and 50 rows? (debug line shows it)
4. **Does the keyboard save two copies in a row** while it stays open?
5. **Does the Action button / Shortcut read the clipboard with or without a prompt?**

---

## 14. Glossary

- **Process:** one running program with its own memory. App, keyboard, share sheet and widget are separate processes.
- **Extension:** a small program embedded in an app that plugs into iOS (share sheet, keyboard, widget).
- **App Group:** a folder several of your programs may share.
- **Entitlement:** a permission stamped in at code-signing time.
- **Provisioning profile:** Apple's signed document saying "this app, on these devices, may use these entitlements."
- **Pasteboard / clipboard:** the same thing. iOS's name is pasteboard.
- **Hash:** a short fingerprint of content, used to spot duplicates.
- **OTP:** one-time password / verification code.
- **Intent:** a small action an app offers to Shortcuts, Siri, the Action button or widgets.
- **Timeline (widgets):** a prepared list of "what to show and when."
- **DTO (data transfer object):** a plain copy of data safe to pass around.
- **Actor:** Swift's tool for safe, one-at-a-time access to shared data.
