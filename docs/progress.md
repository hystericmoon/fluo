Last updated 2026-11-09

## Next up
Session 10 is written up in `docs/release.md`. Decision: no Play Store or App Store release; Fluo is shared as a sideloaded APK with application ID `app.haho.fluo`. Only this remains:
- Run on a physical Android device and do the manual TalkBack script in `docs/accessibility.md`. Nothing has run on hardware.
- If a store release is ever wanted: trademark search, upload keystore, Play Console forms (texts drafted in `docs/release.md` and `docs/privacy.md`).

## Next (hand-off, 2026-11-09)
Branch `session-10-release` (PR #10, stacked on session-9-settings) holds everything, pushed at the time of writing. Sessions 1 to 10 done, plus a post-10 capture fix.
1. Install the debug APK on the phone and verify, in this order: start a session (card should say "Session on"), take a screenshot (it should appear under "Review N new"), Pause then Resume, and share a screenshot to Fluo from the gallery and pick an album. If it fails, read `adb logcat -s FluoCapture` and the card's "Could not start" state (`CaptureController.lastError`).
2. Then check the remaining device risks below: brand file-name heuristic (`ScreenshotFilter`), service surviving idle, Android 14 "selected photos", watching-notification icon.
3. Fluo ships as a sideloaded APK signed with the debug key (no store release). `docs/privacy.md` only matters if that changes.
Toolchain after a clear: Flutter 3.47.9 in /opt/tc/flutter, Android SDK 36 in /opt/tc/android (ANDROID_HOME). Run `git config --global --add safe.directory /opt/tc/flutter`. Do not run two gradle builds at once (lock clash).
The stop hook miscounts unpushed commits here; check `git ls-remote origin <branch>` against `git rev-parse HEAD`.
User asked to pause and resume at 12:20am; no time zone given, so no reminder was scheduled.

## Open items
- Session 11 (2026-11-10): RESOLVED. The user's first Mac screenshot was not captured because it was not saved as a file in the watched folder; once saved to the Desktop it was captured. Capture works. Idea: show the watched folder on the session card ("Watching Desktop") so a screenshot sent to the clipboard or another folder is easy to spot. Run from the `session-11-macos` worktree (`flutter run -d macos`); the main checkout may lack `macos/`. `tool/make_dmg.sh` builds an unsigned DMG. A 60x40 test crop may sit as a pending screen in their album.
- Session 11 (macOS): capture UI copy is still phone wording ("photo access", "this phone", "share it from your gallery"; there is no share target on macOS). Make `albums.dart` copy platform-aware (tests run on a Mac host, so inject the platform rather than reading `Platform` directly). Also not done: a custom screenshot folder outside `~/Desktop` (needs a folder picker with a security-scoped bookmark), drag and drop import, window sizing and desktop layout, an app icon for macOS, menu bar items, release signing and notarisation.
- Post-session 10 (device feedback): FIXED probable cause of "not detected" and a dead Resume button: `Gallery.maxId` put `LIMIT 1` in the sort order, which Android 11+ rejects, so `start` threw and the card stayed on Paused. Now uses `QUERY_ARG_LIMIT`; `start` errors reach Dart, and the card shows "Could not start" with Try again. A row stuck as pending for over a minute no longer blocks the watcher. NOT yet verified on a phone.
- Post-session 10: NEW fallback: Fluo is an Android share target for images (`ShareIntake.kt`, `lib/ui/shared_intake.dart`). Share a screenshot to Fluo, then pick an album or create a new one; it arrives as a pending screen. Cancel discards the shared copy. Sharing does not start a session.
- Session 7: Albums, Triage, Album, Editor and Export are real. Only Settings (session 9) still shows fixed content.
- Session 3: `Shot.width` and `height` are optional because reading them needs an image decode; the capture plugin should supply them.
- Session 3: deleting a pin renumbers the rest, so pin numbers in an exported Claude pack can change between exports. Fine for now; revisit if pins need stable IDs in exports.
- Session 3: no migration beyond v1 exists, so the first real migration is untested. Test it when one is added.
- Session 4: capture is unverified on a device. Risks to check first: (1) the name and folder heuristic on your phone's brand; (2) whether the foreground service survives the app being swiped away and the phone idling; (3) Android 14 "selected photos" handling; (4) the "watching" notification and its icon (it reuses the launcher icon, so it is a grey square on some versions: needs a proper monochrome icon).
- Session 4: a new album starts a session in it, and starting one ends the previous. There is no UI to choose another album for an existing session or to end a session; only Pause and Resume. Decide in session 5.
- Session 4: a crash between storing a shot and acking its inbox file would import that screenshot twice. The window is tiny; add a source id column if it ever shows up.
- Session 4: screenshots taken while paused, or with no session, are dropped (originals stay in the gallery). Intended.
- Session 4: the watcher does not restart after a reboot. The session survives in the database and sync resumes watching the next time the app opens.
- Session 4 (release, session 10): the service uses the `specialUse` foreground type. Google Play needs a declaration and a justification for it in the Play Console. The manifest property text is a draft. Also the debug build has the INTERNET permission (Flutter hot reload); confirm the release build has none, to back the local-only claim.
- Session 8: DONE: screens can be reordered with buttons (Reorder screens mode, plus TalkBack actions). There is no drag reorder; buttons were enough and need no alternative.
- Session 5: Done in Triage leaves unsorted shots pending (they stay in "Review N new").
- Session 6: DECIDED (user was away): discarded screenshots are deleted, rows and files, when Triage is left and on app start. Change `purgeDiscarded` calls if you want a trash instead.
- Session 5: filter chips count screens that have at least one pin of that severity, not pins. The mock does not say which.
- Session 5: on the album screen the filter chips wrap to a second line on narrow phones instead of scrolling, because a half-visible chip is easy to miss.
- Session 5: the Triage card shows the whole screenshot (letterboxed), not a crop, so nothing is hidden while reviewing.
- Session 6: not built, on purpose: blur (only solid redaction), a choice of mark colours (all marks are red), stroke width options, text labels, undo for moves and deletions (undo removes the last added mark only).
- Session 6: accessibility. Pins can be placed, selected, edited, nudged and deleted without touch; every mark can be selected and deleted from the marks list; the crop frame has eight trim actions for screen readers. Drawing a pen stroke, arrow, box or redaction and dragging crop corners still need touch. Revisit in session 8 (TalkBack pass); an idea is preset rectangles ("top third", "whole width") that create boxes and redactions from buttons.
- Session 6: the crop is only applied on export; the canvas shows the cropped view when the crop tool is closed.
- Session 6: large screenshots are decoded at 1600px wide in the Editor. Exports (session 7) should decode at full size.
- Session 6: tests found that `SingleChildScrollView` steals vertical drags from a stock `GestureDetector`/pan; `QuickPanGestureRecognizer` (8px) fixes it. Keep using it for any new drag surface inside a scrolling page. The same tests found a Semantics container that swallowed its buttons: containers that hold controls need `explicitChildNodes: true`.
- Session 7: not verified on a device: the share sheet (`share_plus` provider is in the manifest), opening the ZIP or PDF in other apps, and memory use when exporting a long album of full-size screenshots (they are decoded at up to 4096px wide, one at a time).
- Session 7: the PDF uses the bundled Lexend font, which covers Latin scripts. Captions or notes in other scripts (Arabic, CJK, Cyrillic) show as empty boxes in the PDF only. The ZIP, Markdown and images are unaffected. Fix by bundling a wider font (Noto) if that matters.
- Session 7: the review brief is a fixed template (`briefText` in `lib/export/markdown.dart`). The v2 idea of an editable review-prompt preface is still open.
- Session 7: the long image is cut into numbered parts above 7000px tall (a 19-screen album is about 3 parts). One scrolling image is not always possible on phones.
- Session 7: the PDF cannot be checked for pixel content in tests (it compresses images). Its pages are built from the same baked PNG bytes the other formats use, which are pixel-tested.
- Session 7: exports are written to the app cache and shared as files. If the share sheet fails after the files are written they stay until the next export or app start.
- Session 9: DONE: accent themes and the Reduce motion switch are real and saved.
- Session 8: tests use reduced motion by default (`host(reduceMotion: true)`) because the live border on the session card never stops animating, so `pumpAndSettle` would never finish. Pass `reduceMotion: false` to test motion. After a delete, use `pump()` not `pumpAndSettle()`: the undo fuse is an animation and settling lets it burn.
- Session 8: shadcn_flutter has its own Row, Column and Flex that do not raise RenderFlex overflow errors, so overflow cannot be caught by tests. Text scaling is checked by control size instead (`test/text_scale_test.dart`). Beware of long text in new rows: use `Expanded` plus ellipsis.
- Session 8: the audit found and fixed: text fields with no accessible name (the wrapper and the field were two conflicting nodes), a squeezed control row at large text, and a warning border below 3:1.
- Session 8: the freehand pen has no non-gesture route. Revisit if that matters.
- Session 9: Settings is real. Five themes (all pass contrast; `test/contrast_test.dart` checks every pair per theme), Reduce motion, Auto-update, Wi-Fi only, real version, Check for updates. Settings live in a v3 `settings` table.
- Session 9: DECIDED (user away): updates use Google Play in-app updates, not a GitHub release check, to keep the app free of the INTERNET permission. Consequences: it only works for copies installed from Play (sideloaded copies say "Updates come through Google Play"); the Play flexible-update dialog asks consent when an auto-download starts at launch; it cannot be tested without a Play build (use internal app sharing or an internal test track).
- Session 9: Wi-Fi only means "unmetered connection" (Wi-Fi or Ethernet, not a metered hotspot). The permission added is ACCESS_NETWORK_STATE, which is not internet access.
- Session 9: UNVERIFIED on a device: the Play in-app update flow, `NetworkChannel`, theme switching on hardware.
- Session 9: the test harness `host()` now provides settings, accent and update fakes. `FluoApp.reduceMotion` is `bool?` (null = follow Settings).
- Session 2: screens use fake data from `lib/data/fake_data.dart`; buttons that need real logic are inert (Keep, Discard, Undo, Pause, New album, Export, Check for updates). Each is owned by a later session.
- Session 2: the accent colour is fixed lime in `lib/ui/kit.dart`. Settings only recolours its own preview. Session 9 must route the accent through the theme.
- Session 2: pin badges are lettered circles as in the mocks. Severity chips and dots use shape too. Decide in session 6 whether badges on the canvas also need a shape per severity (CLAUDE.md: letter, shape and colour).
- Session 2: `refs/mocks/*.dc.html` load `./support.js`, which is not in the repo, so the mocks cannot be opened as pages. Screens were built from their markup.
- Session 2: no stub for the version string yet. Settings shows a fixed `Version 0.1.0`.
- Session 1: Settings button border uses `borderStrong` (#6B6B76). Re-check the other shadcn outline controls against the 3:1 floor in session 2.
- Session 10: React Bits licence is MIT + Commons Clause; nothing is ported (see docs/release.md). Trademark and store names need a person.
- Auto-update mechanism not decided.

## History
- 2026-11-09: Kickoff. Name Fluo, FLUO Lexend wordmark, stacked icon, seven mocks done.
- 2026-11-09: Session 1 scaffold. Flutter project, shadcn_flutter 0.0.55, dark lime theme, bundled Lexend and Inter, wordmark, icon, splash, empty Albums. analyze and test pass, debug APK builds.
- 2026-11-09: Session 2 static screens. Albums, Triage, Album (Grid and Flow, severity filters), Editor, Export, Settings, all from the mocks with fake data. Shared kit in `lib/ui/kit.dart`. Tests assert every tap target is at least 44dp and the Export notice, filters and Settings rows react. analyze and test pass.
- 2026-11-09: Session 3 data layer. Album, Shot, Pin, Annotation models, SQLite schema v1, write-once file store, FluoRepo, wired into the Albums list and New album. 36 tests, including write, close, reopen and compare; original bytes verified unchanged by edits. The debug APK bundles libsqlite3 for arm64, armv7 and x86_64.
- 2026-11-09: Session 4 capture. Schema v2 (sessions, the first real migration, tested on an upgraded v1 database). Kotlin watcher service, channel and inbox; Dart CaptureController and session card with permission states. 67 Flutter tests and 11 Kotlin tests. Debug APK builds; merged manifest checked.
- 2026-11-09: Session 5 triage and album. Triage (Keep, Discard, Undo, names, flick with button and TalkBack alternatives) and the Album screen (Grid, Flow order, severity filters, real thumbnails) read and write the database. 100 tests, including a 10-shot session sorted into an album. Fixed a false "Needs photo access" flash on the session card.
- 2026-11-09: Session 6 editor. Crop, pen, arrow, box, pins with severity (shape, letter, colour), redact and captions, stored as vector data. One shared renderer; redaction proven opaque by pixel tests. Discarded screenshots now deleted. About 179 tests. Fixed: vertical strokes scrolling the page, drags starting 18px late, merged semantics containers, zero-length pen strokes.
- 2026-11-09: Session 7 exporters. Claude pack ZIP, PDF, long image and share images, built from one baked render. Redactions proven solid in every format by pixel tests; originals excluded by default and never in PDF or long image. Export screen is real: counts, notices, progress, errors. 225 tests.
- 2026-11-09: Session 8 motion and access. Motion kit (Hold Button, Swipe Row, Undo Fuse, live border, crop frame entry, card entrance) with reduced motion; delete album with undo; button reordering; buttons for adding and moving boxes, arrows and redactions; contrast, label, 44dp, large-text and keyboard audits; docs/accessibility.md.
- 2026-11-09: Session 9 settings and updates. Settings table (migration v3, tested on an upgraded v2 database), five accent themes applied app-wide via `context.accent`, Reduce motion switch, update controller with Wi-Fi only and a 12-hour gap, real version display. 445 tests, Kotlin tests and debug APK pass.
- 2026-11-09: Session 10 release checks. `docs/release.md`: release signing from `key.properties`, app bundle builds, release APK has no INTERNET permission, font licences bundled with a credit and privacy text in Settings, store listing and `specialUse` declaration drafted. Found that the application ID is already taken on Play.
- 2026-11-09: Fixed capture start failure on Android 11+, added Could-not-start state and the share-to-Fluo fallback. 454 tests, Kotlin tests and debug APK pass.
- 2026-11-10: Device check on a Galaxy A55 (Android 17): capture start fix, foreground service (foreground, backgrounded, hard-killed), share-to-Fluo, start-failure states, Triage, editor marks and Claude pack ZIP all passed. Not tried: swiping the app away from recents, a real screenshot gesture.
- 2026-11-10: Session 11 macOS. `macos/` platform added; `MacCaptureSource` (Dart) watches the screenshot folder under the app sandbox; 15 new tests (469 total); verified in the sandboxed app by an integration test that saw a new Desktop screenshot land in the inbox with its size. Not driven through the UI by hand.
