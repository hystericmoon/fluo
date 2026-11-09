Last updated 2026-11-09

## Next up
Session 5: Triage and album. Wire Triage (Keep, Discard, Undo, screen names) and the Album screen (Grid, Flow order, filters) to `FluoRepo`. Pending shots from capture are what Triage reads.

Still owed from sessions 1 to 4: run on a physical Android device. Capture has only been checked by unit tests and a compile; nothing has seen a real MediaStore. On a phone: create an album, allow photos, switch to another app, take a screenshot, come back, and look for "Review 1 new". Also try it with the app swiped away.

## Open items
- Session 3: only the Albums list is real (reads the database, New album works). Album, Triage, Editor and Export still show fake data and need wiring: Triage and Album in session 5, Editor in session 6, Export in session 7.
- Session 3: `Shot.width` and `height` are optional because reading them needs an image decode; the capture plugin should supply them.
- Session 3: deleting a pin renumbers the rest, so pin numbers in an exported Claude pack can change between exports. Fine for now; revisit if pins need stable IDs in exports.
- Session 3: no migration beyond v1 exists, so the first real migration is untested. Test it when one is added.
- Session 4: capture is unverified on a device. Risks to check first: (1) the name and folder heuristic on your phone's brand; (2) whether the foreground service survives the app being swiped away and the phone idling; (3) Android 14 "selected photos" handling; (4) the "watching" notification and its icon (it reuses the launcher icon, so it is a grey square on some versions: needs a proper monochrome icon).
- Session 4: a new album starts a session in it, and starting one ends the previous. There is no UI to choose another album for an existing session or to end a session; only Pause and Resume. Decide in session 5.
- Session 4: Triage still shows fake data. "Review N new" opens it, but it does not read the pending shots yet (session 5).
- Session 4: a crash between storing a shot and acking its inbox file would import that screenshot twice. The window is tiny; add a source id column if it ever shows up.
- Session 4: screenshots taken while paused, or with no session, are dropped (originals stay in the gallery). Intended.
- Session 4: the watcher does not restart after a reboot. The session survives in the database and sync resumes watching the next time the app opens.
- Session 4 (release, session 10): the service uses the `specialUse` foreground type. Google Play needs a declaration and a justification for it in the Play Console. The manifest property text is a draft. Also the debug build has the INTERNET permission (Flutter hot reload); confirm the release build has none, to back the local-only claim.
- Session 2: screens use fake data from `lib/data/fake_data.dart`; buttons that need real logic are inert (Keep, Discard, Undo, Pause, New album, Export, Check for updates). Each is owned by a later session.
- Session 2: the accent colour is fixed lime in `lib/ui/kit.dart`. Settings only recolours its own preview. Session 9 must route the accent through the theme.
- Session 2: pin badges are lettered circles as in the mocks. Severity chips and dots use shape too. Decide in session 6 whether badges on the canvas also need a shape per severity (CLAUDE.md: letter, shape and colour).
- Session 2: `refs/mocks/*.dc.html` load `./support.js`, which is not in the repo, so the mocks cannot be opened as pages. Screens were built from their markup.
- Session 2: no stub for the version string yet. Settings shows a fixed `Version 0.1.0`.
- Session 1: Settings button border uses `borderStrong` (#6B6B76). Re-check the other shadcn outline controls against the 3:1 floor in session 2.
- No button alternative for drag-reorder yet (session 8).
- Check Fluo trademark, domain and store names (session 10).
- Check the React Bits license before porting anything (session 10).
- Auto-update mechanism not decided.

## History
- 2026-11-09: Kickoff. Name Fluo, FLUO Lexend wordmark, stacked icon, seven mocks done.
- 2026-11-09: Session 1 scaffold. Flutter project, shadcn_flutter 0.0.55, dark lime theme, bundled Lexend and Inter, wordmark, icon, splash, empty Albums. analyze and test pass, debug APK builds.
- 2026-11-09: Session 2 static screens. Albums, Triage, Album (Grid and Flow, severity filters), Editor, Export, Settings, all from the mocks with fake data. Shared kit in `lib/ui/kit.dart`. Tests assert every tap target is at least 44dp and the Export notice, filters and Settings rows react. analyze and test pass.
- 2026-11-09: Session 3 data layer. Album, Shot, Pin, Annotation models, SQLite schema v1, write-once file store, FluoRepo, wired into the Albums list and New album. 36 tests, including write, close, reopen and compare; original bytes verified unchanged by edits. The debug APK bundles libsqlite3 for arm64, armv7 and x86_64.
- 2026-11-09: Session 4 capture. Schema v2 (sessions, the first real migration, tested on an upgraded v1 database). Kotlin watcher service, channel and inbox; Dart CaptureController and session card with permission states. 67 Flutter tests and 11 Kotlin tests. Debug APK builds; merged manifest checked.
