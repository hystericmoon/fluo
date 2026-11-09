# Fluo

## Goal
Superfast phone screenshot review app. Take a screenshot, then crop, annotate, caption, put it in an album, and export the album to send to Claude or a person. Built first for reviewing mobile apps; other uses later. Android first, then iOS, Windows, macOS, Linux. Local-only storage, no accounts, no cloud.

## Decisions
- Flutter, one codebase for all platforms. Android capture needs a small Kotlin plugin; other platforms later.
- UI library: `shadcn_flutter` (New York style, standalone). Check the latest version first; it is pre-1.0. Runner-up if it fails: `shadcn_ui`.
- Motion: an internal Flutter motion kit inspired by React Bits (React-only, so nothing is copied). Used: Stack, Swipe Row with Fuse undo, Hold Button, Refine Frame, Star Border. Skipped: backgrounds, text effects, cursor effects. Check the React Bits license before porting any code.
- Storage: SQLite through the `sqlite3` package with hand-written SQL, no ORM. Schema changes are append-only entries in `lib/data/db.dart` (`PRAGMA user_version`). Originals live in `<app docs>/fluo/originals/` as write-once files; the database stores paths relative to that folder. All reads and writes go through `FluoRepo` (`lib/data/repository.dart`).
- Capture: auto-detect new screenshots into a review session, then batch caption and annotate in Triage. On Android a foreground service (`ScreenshotWatchService`) watches MediaStore while a session is on and copies each screenshot into a private inbox at once, so nothing is lost if the Dart side is not running. Dart (`CaptureController`) drains the inbox into the session's album as pending shots on start, resume and a ping, and acks each file after storing it. Creating an album starts a session in it; only one session is active. Detection is a name and folder heuristic (`ScreenshotFilter`).
- Triage: every Keep, Discard and name is written to the database at once, so leaving half way loses nothing and the rest stay pending. Undo only reaches back within the current pass. Flow numbers count kept screens in order.
- Editor: marks are stored in normalised image coordinates (0..1 of the original) and drawn by one renderer (`lib/edit/render.dart`) used for the canvas and, from session 7, for exports. Pin shape, letter and colour carry severity (Bug circle B, UX rounded square U, A11y diamond A) with the pin number. Redactions are opaque black and always painted on top of other marks. Drags on the canvas use `QuickPanGestureRecognizer`, because the stock pan recognizer loses to the page scroll for vertical strokes.
- Discarded screenshots are deleted (rows and files) when Triage is left and on app start.
- Edits are non-destructive: originals are kept, crop and annotations are vector data rendered on export.
- Redactions are baked into exported pixels. Originals are excluded from exports by default, with an explicit toggle to include them.
- Exports: Claude pack (Markdown plus images ZIP with captions, pins and a review brief), PDF, long stitched image, share images.
- Pins carry a severity: Bug, UX or A11y. Each has a letter, a shape and a colour, so colour is never the only signal.
- Brand: name Fluo. Wordmark FLUO in Lexend 600, +0.14em tracking, lime on dark. App icon is the stacked F L / U O on a dark tile. No separate F mark and no highlighter stroke in the logo.
- Default theme is neon lime `#C8FF3D` on dark; Settings offers other colours. The logo stays lime in every theme.

## Commands
Flutter 3.47 stable, `shadcn_flutter` 0.0.55. Android SDK 36 (set `ANDROID_HOME`).
- Get packages: `flutter pub get`
- Run: `flutter run` (device or emulator)
- Analyze: `flutter analyze`
- Test: `flutter test`
- Debug APK: `flutter build apk --debug` -> `build/app/outputs/flutter-apk/app-debug.apk`
- Kotlin unit tests: `cd android && ./gradlew :app:testDebugUnitTest` (needs `ANDROID_HOME`)
- Regenerate launcher icons: `python3 -I tool/make_icons.py` (needs Pillow)

Notes: Lexend and Inter are bundled variable fonts in `assets/fonts/` (weight via `FontVariation('wght', n)`), so the app needs no network. Tokens live in `lib/theme/tokens.dart` and mirror `refs/mocks`.

## Pointers
- `docs/spec.md` scope and non-goals
- `docs/plan.md` numbered sessions
- `docs/progress.md` what is next
- `refs/mocks/` the six core screens plus splash; open `canvas.json` boards. Source of truth for UI.
- Tracker: docs/progress.md
