# ImHim Keyboard — iOS custom-keyboard extension

System keyboard replacement that reads the user's most recent screenshot
and writes three reply options straight into whatever text field they're
in — iMessage, Hinge, Tinder, anywhere. Same `/rizz/reply` backend the
in-app Rizz screen already uses, no app switch.

## What's in this folder

| File                              | Role                                                  |
| --------------------------------- | ----------------------------------------------------- |
| `KeyboardViewController.swift`    | The visible keyboard. Owns the four states (waiting / loading / replies / error). |
| `ScreenshotScanner.swift`         | Polls `PHPhotoLibrary` for the latest screenshot, freshness-gated to 90s. |
| `RizzClient.swift`                | POSTs the screenshot to `mirrorly-production.up.railway.app/rizz/reply`. |
| `Theme.swift`                     | Colours + typography mirroring `lib/theme/app_colors.dart`. |
| `Info.plist`                      | `NSExtension` config, `RequestsOpenAccess=YES`, photo library usage string. |
| `ImHimKeyboard.entitlements`      | App Group `group.com.mirrorly.app.shared`.            |

## One-time Xcode wiring

The Swift sources alone don't make the target — Xcode needs to know about
it. Two paths, both idempotent:

### A) Script (preferred — works in CI)

```bash
sudo gem install xcodeproj      # one-time on a fresh machine
ruby ios/scripts/add_keyboard_target.rb
```

The script:

1. Creates an `ImHimKeyboard` app-extension target if it doesn't exist.
2. Adds the four `.swift` files + `Info.plist` + entitlements to it.
3. Sets `INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS`, bundle ID,
   `IPHONEOS_DEPLOYMENT_TARGET=15.5`, `SWIFT_VERSION=5.0`.
4. Adds the "Embed App Extensions" copy phase to Runner so the
   `ImHimKeyboard.appex` lands in `Runner.app/PlugIns/`.
5. Makes Runner depend on the extension so the build order is right.
6. Wires `Runner.entitlements` onto the Runner target so the main app
   joins the same App Group.
7. Saves the project. Safe to re-run.

### B) Xcode UI (one-off, if you don't want Ruby)

1. File → New → Target → Custom Keyboard Extension.
2. Product Name `ImHimKeyboard`, Bundle ID `com.mirrorly.app.keyboard`.
3. Add the four `.swift` files in this folder to the new target's
   Compile Sources.
4. Replace the generated `Info.plist` with the one here.
5. Add `ImHimKeyboard.entitlements` (Signing & Capabilities → App Groups
   → enable `group.com.mirrorly.app.shared`).
6. On the Runner target: Signing & Capabilities → App Groups → enable
   the same group.
7. Build, ship.

## App Group

Both targets need the App Group `group.com.mirrorly.app.shared`. The
group must also be registered on the Apple Developer portal under
Certificates / IDs / App Groups. The Flutter side reads / writes to it
via the standard `MMKV` / shared-preferences-style suite name (see
`lib/services/keyboard_install_service.dart`).

## Approval / privacy posture

Apple reviews keyboards harder than normal apps. Things that keep us
clean:

- **No keystroke logging.** We never touch what the user types.
- **No telemetry from inside the extension.** Even crash reports stay
  off — Firebase Analytics is not initialised in this binary.
- **No background activity.** Polling stops the moment the keyboard
  is dismissed.
- **`RequestsOpenAccess=YES`** is needed for both the network call AND
  Photo Library access. Users see Apple's "can transmit anything you
  type" warning — we walk them through it in the Flutter onboarding
  flow at `/keyboard-install`.
- **Photo Library usage string** in `Info.plist` clearly states what
  the screenshot is used for and that we don't store it.

## Local development

Custom keyboards are flaky on the iOS simulator (no Photo Library, no
"Allow Full Access" toggle in some versions). Always test on a real
device. After installing the build:

1. Settings → General → Keyboard → Keyboards → Add New Keyboard… → ImHim
   Keyboard.
2. Settings → General → Keyboard → Keyboards → ImHim Keyboard → toggle
   "Allow Full Access" on.
3. Open Messages, tap the globe icon to switch keyboard, take a
   screenshot in another app, switch to Messages, the keyboard surfaces
   the three replies.
