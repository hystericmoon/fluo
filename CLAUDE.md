# Fluo

## Goal
Superfast phone screenshot review app. Take a screenshot, then crop, annotate, caption, put it in an album, and export the album to send to Claude or a person. Built first for reviewing mobile apps; other uses later. Android first, then iOS, Windows, macOS, Linux. Local-only storage, no accounts, no cloud.

## Decisions
- Flutter, one codebase for all platforms. Android capture needs a small Kotlin plugin; other platforms later.
- UI library: `shadcn_flutter` (New York style, standalone). Check the latest version first; it is pre-1.0. Runner-up if it fails: `shadcn_ui`.
- Motion: an internal Flutter motion kit inspired by React Bits (React-only, so nothing is copied). Used: Stack, Swipe Row with Fuse undo, Hold Button, Refine Frame, Star Border. Skipped: backgrounds, text effects, cursor effects. Check the React Bits license before porting any code.
- Storage: SQLite through the `sqlite3` package with hand-written SQL, no ORM. Schema changes are append-only entries in `lib/data/db.dart` (`PRAGMA user_version`). Originals live in `<app docs>/fluo/originals/` as write-once files; the database stores paths relative to that folder. All reads and writes go through `FluoRepo` (`lib/data/repository.dart`).
- Capture: auto-detect new screenshots into a review session, then batch caption and annotate in Triage. On Android a foreground service (`ScreenshotWatchService`) watches MediaStore while a session is on and copies each screenshot into a private inbox at once, so nothing is lost if the Dart side is not running. Dart (`CaptureController`) drains the inbox into the session's album as pending shots on start, resume and a ping, and acks each file after storing it. Creating an album starts a session in it; only one session is active. Detection is a name and folder heuristic (`ScreenshotFilter`).
- macOS capture (`lib/capture/mac_capture_source.dart`, plain Dart, no plugin): watches the screenshot folder (`defaults read com.apple.screencapture location`, else the Desktop) with `Directory.watch` plus a 2 s poll, copies each new `Screenshot ...` file into `<app support>/fluo/inbox`, same drain and ack contract as Android. No background service: a `capture_cursor` file lets a restart pick up shots taken while Fluo was closed; Pause or stop clears it. The app sandbox stays ON; the only extra entitlement is a read-only exception for `~/Desktop/`, so a custom screenshot folder will not be readable until that is widened. Inside the sandbox `HOME` is the container, so the real home is rebuilt from `USER`. No share-to-Fluo on desktop yet.
- Triage: every Keep, Discard and name is written to the database at once, so leaving half way loses nothing and the rest stay pending. Undo only reaches back within the current pass. Flow numbers count kept screens in order.
- Editor: marks are stored in normalised image coordinates (0..1 of the original) and drawn by one renderer (`lib/edit/render.dart`) used for the canvas and, from session 7, for exports. Pin shape, letter and colour carry severity (Bug circle B, UX rounded square U, A11y diamond A) with the pin number. Redactions are opaque black and always painted on top of other marks. Drags on the canvas use `QuickPanGestureRecognizer`, because the stock pan recognizer loses to the page scroll for vertical strokes.
- Discarded screenshots are deleted (rows and files) when Triage is left and on app start.
- Motion kit (`lib/motion/`): Hold Button (hold, or tap twice), Swipe Row, Undo Fuse (undo bar for deletes; deletes are final only when it burns), FluoStarBorder (live border on the session card), crop frame entry, Triage card entrance. Every motion respects `reducedMotion(context)` (system setting or the in-app `MotionScope`). Every gesture has a non-gesture alternative; see `docs/accessibility.md`. Put TalkBack actions on the control itself (`Pressable.actions`), and give containers that hold controls `explicitChildNodes: true`.
- Edits are non-destructive: originals are kept, crop and annotations are vector data rendered on export.
- Redactions are baked into exported pixels. Originals are excluded from exports by default, with an explicit toggle to include them.
- Exports: Claude pack (Markdown plus images ZIP with captions, pins and a review brief), PDF, long stitched image, share images. All built from images rendered by `renderShotPng` (`lib/export/render_shot.dart`), which uses the editor's `paintEdit`, so crop, marks and redactions are baked into pixels before anything is written. `ExportService` writes to a temp folder that is cleared before each export and at launch, then hands the files to the system share sheet (`share_plus`). Originals are only added to the Claude pack and Share images, and only if the switch is on; PDF and long image never carry them. A long album is split into numbered long-image parts (max 7000px each).
- Pins carry a severity: Bug, UX or A11y. Each has a letter, a shape and a colour, so colour is never the only signal.
- Brand: name Fluo. Wordmark FLUO in Lexend 600, +0.14em tracking, lime on dark. App icon is the stacked F L / U O on a dark tile. No separate F mark and no highlighter stroke in the logo.
- Default theme is neon lime `#C8FF3D` on dark; Settings offers violet, cyan, orange and pink. The choice is saved in SQLite (`settings` table, `AppSettings`) and read through `context.accent` (`lib/theme/accent.dart`); never hard-code lime (`test/no_hardcoded_accent_test.dart` fails if you do). The logo and exports stay lime in every theme.
- Updates: Google Play in-app updates (`in_app_update`), chosen over a GitHub release check because that needs the INTERNET permission and would break the local-only promise. Only works for copies installed from Play; others say so. "Wi-Fi only" asks Android whether the connection is unmetered (`NetworkChannel.kt`, needs only ACCESS_NETWORK_STATE). Auto-check runs on launch at most every 12 hours.

## Commands
Flutter 3.47 stable, `shadcn_flutter` 0.0.55. Android SDK 36 (set `ANDROID_HOME`).
- Get packages: `flutter pub get`
- Run: `flutter run` (device or emulator)
- Analyze: `flutter analyze`
- Test: `flutter test`
- macOS: `flutter run -d macos`, `flutter build macos --debug` -> `build/macos/Build/Products/Debug/fluo.app`. The `macos/` folder is generated; `flutter create` rewrites `.metadata` and `analysis_options.yaml`, so check the diff.
- Debug APK: `flutter build apk --debug` -> `build/app/outputs/flutter-apk/app-debug.apk`
- Kotlin unit tests: `cd android && ./gradlew :app:testDebugUnitTest` (needs `ANDROID_HOME`)
- Release: `flutter build appbundle --release` (signs with `android/key.properties` if present, else the debug key, which Play rejects). `docs/release.md` has the release checks.
- Regenerate launcher icons: `python3 -I tool/make_icons.py` (needs Pillow)

Notes: Lexend and Inter are bundled variable fonts in `assets/fonts/` (weight via `FontVariation('wght', n)`), so the app needs no network. Tokens live in `lib/theme/tokens.dart` and mirror `refs/mocks`.

## Pointers
- `docs/spec.md` scope and non-goals
- `docs/plan.md` numbered sessions
- `docs/progress.md` what is next
- `docs/accessibility.md` the accessibility checks, the gesture-to-alternative table and a manual TalkBack script
- `refs/mocks/` the six core screens plus splash; open `canvas.json` boards. Source of truth for UI.
- Tracker: docs/progress.md
