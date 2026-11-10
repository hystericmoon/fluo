# Release checks (session 10)

Checked 2026-11-09 with Flutter 3.47.9 stable and Android SDK 36 (build-tools 36.0.0).
Status words: **cleared** (done and verified), **changed** (something was wrong or missing and was fixed in this branch), **needs a person** (cannot be settled from the repo).

| # | Item | Status |
|---|------|--------|
| 1 | Name, trademark, domain, store names | changed: application ID is now `app.haho.fluo`; no store release planned (see 1) |
| 2 | React Bits licence | cleared (with a note) |
| 3 | Release signing, app bundle | changed |
| 4 | Store listing draft | changed (drafted below) |
| 5 | Play declaration, `specialUse` service | changed (text drafted below, the form needs a person) |
| 6 | No `INTERNET` permission in release | cleared |
| 7 | Font (OFL) licences and credit | changed |
| 8 | Privacy statement | changed |

## 1. Name, trademark, domain, store names

**Decision (2026-11-09): no Play Store or App Store release.** Fluo is shared as a sideloaded APK. The application ID is now `app.haho.fluo` (changed from `app.fluo.fluo`, which a different Play app already uses), and the listing title, if one is ever needed, is "Fluo: Screenshot Review". Because there is no store release, the trademark search, Play Console forms, upload keystore and listing assets below are only needed if that changes. Sideload builds are signed with the debug key (no `key.properties`); updates only install over a build signed with the same key. In-app updates only work for Play installs, so sideloaded copies say so.

Findings from the original check, kept for reference:

Found from here:
- **BLOCKER: the Android application ID `app.fluo.fluo` is already taken on Google Play.** `https://play.google.com/store/apps/details?id=app.fluo.fluo` is a live listing named "Fluo" by developer Qodar (an expenses, mileage and visits app, site fluo.com.br, last updated Jul 2024). A package name is unique across Play and cannot be changed after the first upload, so a new ID must be chosen **before** any upload. It was not changed here because the ID should follow a domain you own. Suggested pattern: reverse of a domain you control (for example `app.getfluo.fluo` only if you register getfluo.app). Only `applicationId` in `android/app/build.gradle.kts` needs to change; `namespace` and the Kotlin packages can stay `app.fluo.fluo`. Check the new ID the same way (a 404 means free). The platform channel names (`app.fluo/capture`, `app.fluo/network`) are plain strings, not the application ID, so they do not need to change.
- **The name "Fluo" is already used by another Play app** (different field). Play does not require unique titles, but this raises confusion and trademark risk. Needs a trademark search (EUIPO, USPTO, INPI Brazil, WIPO Global Brand Database; classes 9 and 42) and a decision: keep Fluo, or use a longer store title such as "Fluo: Screenshot Review".
- **Domains** (DNS lookup only, which shows that a name resolves, not who owns it or whether it is for sale): `fluo.com`, `fluo.app`, `fluo.dev` and `getfluo.app` all resolve, so they are in use. `usefluo.com` does not resolve and may be free. Confirm in a registrar. `fluo.app` serves an expired TLS certificate.
- Not checked: App Store, Microsoft Store, Snap and Flathub names (later platforms), social handles, GitHub org names.

## 2. React Bits licence: cleared

Real text fetched from `DavidHDev/react-bits` (`LICENSE.md`): **MIT + Commons Clause License Condition v1.0**, copyright 2026 David Haz. It lets you use the components in an application or product, including a paid one, but you may not sell, sublicense or redistribute the components themselves, "whether alone, in a bundle, or as a ported version".
- Nothing was copied: `grep -ri "react.bits" lib test` finds no reference and no code, and the kit in `lib/motion/` (Hold Button, Swipe Row, Undo Fuse, Star Border) is original Flutter code. So no attribution or licence file is required.
- Note: it is not plain MIT. Shipping a Flutter port of a React Bits component would count as a "ported version" of the component and is the case the Commons Clause restricts. Keep the kit original, and do not publish it as a standalone package that copies their code. If code is ever ported, ask the author first.

## 3. Signing and app bundle: changed

- `android/app/build.gradle.kts` now reads `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) and signs the release build with it. The file and keystores are already git-ignored (`android/.gitignore`); nothing secret is committed.
- Verified with a throwaway keystore (deleted afterwards): the release APK was signed with that key. Without `key.properties` the release build falls back to the debug key so it still builds, but **that build must not be uploaded** (Play rejects it).
- `flutter build appbundle --release` builds: `build/app/outputs/bundle/release/app-release.aab`, 62.6 MB. The release APK is 63.5 MB.
- Needs a person: create the upload keystore and keep a backup, enrol in Play App Signing, and set the final `applicationId` (item 1) first.

```bash
keytool -genkeypair -v -keystore ~/fluo-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```
Then create `android/key.properties` with the four keys above, and run `flutter build appbundle --release`.

## 4. Store listing draft: changed (drafted)

Title (30 max): **Fluo: Screenshot Review** (final name depends on item 1)

Short description (80 max): **Review app screenshots fast: crop, mark up, caption, export. All on your phone.**

Long description:
> Fluo is a fast way to review an app on your phone. Turn on a review session, take screenshots as you go, then sort them in one pass.
>
> • Auto-collects new screenshots into a session while it is on
> • Triage: Keep, Discard and name each screen in seconds, with undo
> • Crop and mark up: pen, arrow, box, numbered pins for Bug, UX and Accessibility issues (each has a letter, a shape and a colour), and solid redaction for private details
> • Albums, in screen order, with filters by issue type
> • Export a Claude pack (Markdown, images and a review brief), a PDF, a long image or the images themselves
> • Originals are kept and never changed; marks are applied only when you export
> • Five colour themes, reduced-motion option, works with TalkBack
>
> Private by design: no account, no cloud, no ads. Your screenshots stay on your phone. Nothing leaves it except what you choose to share.

Screenshots (phone, 1080×1920 or larger, at least 4, in this order): 1 Albums with an active session; 2 Triage card; 3 Album grid with severity filters; 4 Editor with pins; 5 Redaction; 6 Export (Claude pack); 7 Settings themes. Also needed: 512×512 icon, 1024×500 feature graphic. Capture on a real device (none exist yet).

Category: Tools or Productivity. Contact email and privacy policy URL: needs a person (Play requires a URL; the text can be the Privacy section below).

Data safety answers:
- Collects or shares any user data: **No**.
- Data encrypted in transit: not applicable (no data is transmitted by the app).
- Account creation: **none**, so no account deletion URL.
- Data deletion: all data is on the device; uninstalling deletes it.
- The share sheet hands files to an app the person picks; that is a user action, not collection by Fluo.
- Play's own in-app update service is used; it is part of Google Play, not Fluo code.
- Ads: none. Target audience: 13+ (a professional tool).
- Permissions to justify in the form: `READ_MEDIA_IMAGES` and `READ_MEDIA_VISUAL_USER_SELECTED` (detect new screenshots; core function), `POST_NOTIFICATIONS` (the "watching" notice), `ACCESS_NETWORK_STATE` (only to ask whether the connection is metered, for "Wi-Fi only" updates).
- Note: Play may question broad photo access. Fluo asks for photos only to find new screenshots. If review pushes back, the fallback is the Android photo picker, which loses auto-detection.

## 5. `specialUse` foreground service declaration: changed (drafted)

In the Play Console (App content, Foreground service permissions) pick **Other / specialUse** and paste:

> Fluo's screenshot watcher runs only while the person has switched on a review session. It observes the device's media store for new screenshots and copies each one into the app's private folder so none are lost while the person is in the app being reviewed. No predefined foreground service type fits: it is not media playback, location, data sync or camera. It starts when the person starts or resumes a session, shows a persistent notification while on, and stops when the session is paused. It makes no network connections.

Also needed: a short demo video (Play asks for one) showing the person starting a session, taking a screenshot in another app, and the persistent notification. Needs a person with a device. The manifest property text (`PROPERTY_SPECIAL_USE_FGS_SUBTYPE`) was re-read and matches this justification.

## 6. No `INTERNET` permission in release: cleared

`flutter build apk --release` then `aapt2 dump badging`: the release APK declares only `READ_MEDIA_IMAGES`, `READ_MEDIA_VISUAL_USER_SELECTED`, `READ_EXTERNAL_STORAGE` (max SDK 32), `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS`, `ACCESS_NETWORK_STATE`, plus the app-private `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. A count of `android.permission.INTERNET` in `aapt2 dump permissions` is 0. For contrast, the debug APK does carry it (hot reload). targetSdk 36, versionName 0.1.0, versionCode 1. Re-run after adding any plugin: a dependency's manifest can merge in INTERNET.

```bash
$ANDROID_HOME/build-tools/36.0.0/aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk | grep -i internet
```

## 7. Font licences: changed

- Added `assets/licenses/Lexend-OFL.txt` (from `google/fonts`, Lexend, Copyright 2018 The Lexend Project Authors) and `assets/licenses/Inter-OFL.txt` (from `rsms/inter`, Copyright 2016 The Inter Project Authors). Both are SIL Open Font License 1.1, which allows bundling and embedding in an app; the fonts are not sold on their own and are not renamed.
- Settings now has a "Privacy and credits" card naming both fonts and showing the full licence texts offline (`test/settings_test.dart` covers it). Declared under `flutter: assets:` in `pubspec.yaml`.
- Note: the OFL reserved font name for Lexend is "RevReading Lexend"; the bundled file is unmodified, so this is not an issue.

## 8. Privacy: changed

Shown in Settings, "Privacy and credits": *Fluo keeps everything on this phone. There are no accounts and no cloud. Nothing leaves the phone except what you choose to share from the export screen.* This matches item 6. A draft policy page is in `docs/privacy.md` (two TODOs: operator name and contact email, plus the date). Play still needs it hosted at a public URL, which needs a person.

## Not cleared from here

1. Choose a new application ID and settle the name (item 1). This blocks the first upload.
2. Trademark search and domain purchase.
3. Upload keystore, Play Console account, listing form, data safety form, foreground service form and demo video.
4. Hardware: nothing has run on a physical Android device, and the TalkBack script in `docs/accessibility.md` is still owed. The Play in-app update flow can only be tested from a Play build (internal test track or internal app sharing).
5. Screenshots for the listing.

## macOS signing and notarisation

`tool/make_dmg.sh` builds `build/Fluo.dmg`. Run bare, it is ad-hoc signed and testers must right-click the app and choose Open once. To ship a DMG that opens without a warning it must be signed with a Developer ID, notarised by Apple and stapled. The script does all of it when `DEVELOPER_ID` (and `NOTARY_PROFILE`) are set. Needs a Mac with Xcode command line tools; nothing here has been run yet because it needs the Apple Developer ID.

One-time setup (needs the paid Apple Developer Program):

1. In Xcode, Settings > Accounts > Manage Certificates, add **Developer ID Application**. Or create it at developer.apple.com > Certificates and import it into the login keychain. Note the **Team ID**.
2. Check it is there. The identity string is what `DEVELOPER_ID` takes:
   ```bash
   security find-identity -v -p codesigning
   # "Developer ID Application: Your Name (TEAMID)"
   ```
3. Make an app-specific password at account.apple.com > Sign-In and Security > App-Specific Passwords, then store a notary profile. The password goes into the keychain, never into the repo or the script:
   ```bash
   xcrun notarytool store-credentials fluo-notary --apple-id YOUR_APPLE_ID --team-id TEAMID
   ```

Each release:

```bash
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=fluo-notary tool/make_dmg.sh
```

What the script does, in order: `flutter build macos --release`, then `codesign --options runtime --timestamp` on every nested framework, dylib and helper (deepest first, no `--deep`), then on the app with `macos/Runner/Release.entitlements` (the sandbox stays on); `codesign --verify`; builds and signs the DMG; `notarytool submit --wait`; `stapler staple` and `stapler validate`; `spctl --assess`.

Checks after it finishes, on a Mac that has never seen the build (or after `xattr -w com.apple.quarantine "0081;00000000;Safari;" build/Fluo.dmg`): the DMG opens with no Gatekeeper warning, the app launches, capture and the folder picker work, drag and drop works.

If notarisation says Invalid: `xcrun notarytool log <submission-id> --keychain-profile fluo-notary`. Usual causes are an unsigned nested binary or a missing secure timestamp.

Notes:
- `Release.entitlements` has a `temporary-exception.files.home-relative-path.read-only` for `/Desktop/`. Developer ID notarisation allows it; the Mac App Store would not. If Fluo ever goes to the Mac App Store, drop the exception and rely on the folder picker.
- Hardened runtime needs no extra entitlements for a release Flutter build (AOT, no JIT).
