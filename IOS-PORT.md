# Porting Red Wedge Timer to iPhone / the App Store

Decided 2026-09-11. The macOS app in `swift/` works; this is the plan to ship the
same thing on iPhone, reusing the App Store Connect tooling from
`~/IT-Projects/toddler-games`.

## Submitted

Version 1.0 (build 2) went to review on 13 September 2026, 09:06 UTC, and is
WAITING_FOR_REVIEW. Release type is AFTER_APPROVAL, so approval publishes it
without anyone pressing anything. Free worldwide, base territory CHE.

Everything on the listing was set through `asc-store.mjs` except two things that
only exist in the web UI: App Privacy (published, "data not collected") and the
errors that block submission, which the version page shows when you press "Add
for Review" — that page is the fastest way to find what the API will only call
"not in valid state". The two it caught: the version's `copyright` attribute and
a price tier.

If Apple rejects: fix, bump `CURRENT_PROJECT_VERSION` in the Xcode project, run
`ios/release.sh`, then `node ios/asc-store.mjs build` and `submit` again.

## Status

Done, verified on a booted iPhone simulator: the shared sources build for both
platforms, the layout fits a 393pt phone without scrolling, and the app runs.

```
./swift/build.sh                                   # the Mac app
cd ios && xcodebuild -project RedWedgeTimer.xcodeproj -scheme RedWedgeTimer \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build                    # the phone app
```

The app record exists: **Apple ID 6811064404**, SKU `redwedgetimer`,
https://appstoreconnect.apple.com/apps/6811064404/distribution — that id is what
the metadata and submit scripts need, in place of toddler-games' 6447790341.

Left to do:

1. ~~Register the bundle id, certificate and profile~~ — done via
   `asc-provision.mjs`; team is `MTV8K47N4D`.
2. ~~Create the app record~~ — done.
3. Run `ios/install-signing.sh` once, by hand: it imports the distribution
   identity into the login keychain and installs the profile. The agent's
   sandbox refuses keychain writes, so this one is always yours.
4. `ios/release.sh` — archive, export, upload with altool.
4. Point the toddler-games `asc-metadata.mjs` / `asc-submit.mjs` at the new app
   id and run them.
5. Screenshots at 6.9" and 6.5", description, keywords, age rating, privacy
   answers (the app collects nothing).

## The one hard requirement

The alarm must fire with the screen off. Everything else is cosmetic. Two
mechanisms, and we want both:

1. **Background audio** — `AVAudioSession` category `.playback`, plus
   `UIBackgroundModes: [audio]` in Info.plist. Keeps the repeating three-tone
   alarm audible while the app is backgrounded.
2. **A scheduled local notification** — `UNCalendarNotificationTrigger` (or
   interval) set for the moment the disk empties, carrying a
   `UNNotificationSound`. This is the safety net for when iOS suspends the app
   anyway. Schedule it on Start, cancel it on Pause/Reset.

Do not rely on a repeating `Timer` surviving suspension: it does not. On
`willEnterForeground`, recompute `remaining` from the stored end date.

## Code changes, file by file

| file | change |
| --- | --- |
| `Beeper.swift` | Configure `AVAudioSession.sharedInstance()` (`.playback`, `.mixWithOthers` off) before starting the engine. Replace `NSApplication.shared.requestUserAttention` with a haptic (`UINotificationFeedbackGenerator`). Keep the synthesised buffers — they port unchanged. |
| `TimerModel.swift` | Store `endsAt` in `UserDefaults` so a cold launch can recover a running timer. Add notification scheduling/cancelling alongside `start()` / `pause()` / `reset()`. |
| `DialView.swift` | Drop `import AppKit` and the `NSCursor` hover block. The `Canvas` drawing and the drag gesture are already portable. |
| `TimerScreen.swift` | Replace the fixed window paddings with `safeAreaInsets`; the 5-column preset grid needs to survive a 375 pt wide screen (it fits, but check the 1-minute chip). |
| `RedWedgeTimerApp.swift` | Drop `.defaultSize` / `.windowResizability`, which are macOS-only. |
| `Palette.swift` | Unchanged. |

## Getting an .ipa without clicking around Xcode

`swiftc` + a hand-built bundle got us a Mac app, but the App Store wants a
signed archive, which means an Xcode project. Two ways in:

- **Preferred:** hand-write a minimal `RedWedgeTimer.xcodeproj/project.pbxproj`
  (single app target, the six sources, an asset catalog), then everything after
  that is CLI: `xcodebuild -project ... -scheme ... archive` →
  `xcodebuild -exportArchive -exportOptionsPlist`.
- **Fallback:** create the project once in Xcode's GUI, commit it, and never
  open Xcode again.

Then the binary upload, which `toddler-games/scripts/usage.md` currently lists as
the manual step, is scriptable with the same API key:

```
xcrun altool --upload-app -f build/RedWedgeTimer.ipa -t ios \
  --apiKey "$APPSTORECONNECT_KEY_ID" --apiIssuer "$APPSTORECONNECT_ISSUER_ID"
```

The `.p8` has to sit in `~/.appstoreconnect/private_keys/` for `altool` to find
it. Worth closing that gap for toddler-games at the same time.

## Signing

Needs a distribution certificate and an App Store provisioning profile for a new
bundle id — `com.bersling.redwedgetimer` is what the Mac app already uses. Both
can be created through the App Store Connect API with the existing key, or by
hand at developer.apple.com once.

## App Store Connect

Reuse the toddler-games scripts, pointing them at the new app id:

```
node scripts/asc.mjs apps                                  # auth check
node scripts/asc-metadata.mjs --version 1.0.0 --apply      # create version + metadata
node scripts/asc-submit.mjs  --version 1.0.0 --build 1 --apply
```

Note `APP_ID` is hardcoded to `6447790341` in `scripts/asc.mjs` — it needs a
flag or a copy for this app.

Still to produce, none of it code: app icon (1024 plus the set), 6.9" and 6.5"
screenshots, description, keywords, support URL, privacy questionnaire (this app
collects nothing, which makes the questionnaire short), and an age rating.
