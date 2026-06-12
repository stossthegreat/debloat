# ImHim Share Extension

iOS Share Extension that delivers the **WingAI-style screenshot-share
workflow** to ImHim. End-to-end flow:

1. User is inside iMessage (or anywhere).
2. User takes a screenshot.
3. User taps **Share**.
4. User picks **ImHim** from the iOS Share Sheet.
5. The Share Extension writes the screenshot to the App Group container
   and deep-links the main Flutter app via `imhim://rizz?source=share`.
6. The main app foregrounds, the Flutter side reads the bytes off the
   App Group, navigates straight to `/rizz`, and the existing OCR + AI
   reply pipeline runs.

## Folder layout

```
ios/
├── ImHimShare/                            ← THIS folder
│   ├── ShareViewController.swift           ← extension entry point
│   ├── Info.plist                          ← NSExtension config
│   ├── ImHimShare.entitlements             ← App Group
│   └── README.md
├── Runner/
│   ├── AppDelegate.swift                   ← URL + MethodChannel
│   ├── Info.plist                          ← URL scheme registered
│   └── Runner.entitlements                 ← App Group (matching)
├── scripts/
│   └── add_share_target.rb                 ← wires the target
└── Runner.xcodeproj/...

lib/
├── main.dart                               ← intake wired at boot
├── navigation/app_router.dart              ← /rizz accepts payload
├── services/
│   └── share_intake_service.dart           ← MethodChannel bridge
└── screens/game/rizz/rizz_reply_screen.dart ← consumes the bytes
```

## Step-by-step Xcode setup

### One-time setup (run once, then forget)

```bash
sudo gem install xcodeproj
ruby ios/scripts/add_share_target.rb
git add ios/Runner.xcodeproj
git commit -m "wire ImHimShare target"
git push
```

The script:

1. Creates the `ImHimShare` app-extension target with bundle id
   `com.mirrorly.app.share`.
2. Adds `ShareViewController.swift` to the new target.
3. Links `Social.framework`.
4. Sets `INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS`, deployment
   target, Swift version, automatic signing, dev team.
5. Adds the **Embed App Extensions** copy phase to Runner so the
   `ImHimShare.appex` lands in `Runner.app/PlugIns/`.
6. Wires Runner → ImHimShare dependency.
7. Points Runner at its `Runner.entitlements` (which declares the
   shared App Group).

### Apple Developer portal — one-time, ~2 minutes from a phone

Open the **Apple Developer** app on phone, sign in:

1. **Certificates, Identifiers & Profiles → Identifiers → +**
   - App IDs → App → Continue.
   - Description: "ImHim Share Extension".
   - Bundle ID: `com.mirrorly.app.share` (Explicit).
   - Capabilities: tick **App Groups**.
   - Continue → Register.

2. **Certificates, Identifiers & Profiles → Identifiers → +**
   - App Groups → Continue.
   - Description: "ImHim Shared Container".
   - Identifier: `group.com.mirrorly.app.shared`.
   - Continue → Register.

3. Back to the existing `com.mirrorly.app` App ID:
   - Tick **App Groups** capability.
   - Configure → check `group.com.mirrorly.app.shared`. Save.

4. Same for the new `com.mirrorly.app.share` App ID:
   - Configure App Groups → check the same group. Save.

5. **Profiles** — let Xcode / Codemagic automatic provisioning
   regenerate the App Store profile so it covers both bundle ids.
   With automatic signing this happens on the next build.

### Verifying

After the next Codemagic build:

1. Install the IPA on a real device.
2. Take a screenshot of any chat.
3. Tap the screenshot preview, hit **Share**.
4. Scroll the share sheet — **ImHim** is in the row of app icons.
5. Tap it.
6. App opens, lands on `/rizz`, AI replies appear in a few seconds.

## What lives where

| File                                            | Job                                                      |
| ----------------------------------------------- | -------------------------------------------------------- |
| `ShareViewController.swift`                     | Reads the shared image, writes to App Group, opens host. |
| `Info.plist`                                    | Declares the extension + activation rule (images only).  |
| `ImHimShare.entitlements`                       | App Group on the extension side.                         |
| `ios/Runner/Runner.entitlements`                | App Group on the main app side.                          |
| `ios/Runner/AppDelegate.swift`                  | Handles `imhim://` URLs, exposes `pullPendingShare`.     |
| `ios/Runner/Info.plist`                         | Registers `imhim` URL scheme.                            |
| `lib/services/share_intake_service.dart`        | Flutter side of the MethodChannel.                       |
| `lib/main.dart`                                 | Wires the listener, navigates on first frame.            |
| `lib/screens/game/rizz/rizz_reply_screen.dart`  | Auto-fires OCR + reply when `preloadedScreenshot` is set. |
