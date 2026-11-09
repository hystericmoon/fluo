Last updated 2026-11-09

## Next up
Session 6: Editor. Crop, pen, arrow, box, pins with severity, redact, captions, all stored as vector data through `FluoRepo` (`setCrop`, `addPin`, `addAnnotation`, `loadEdit` already exist). Tapping a tile in an album currently opens the static Editor with fake content; replace it with the real shot.

Still owed from sessions 1 to 5: run on a physical Android device. Capture (session 4) and the Triage flick gesture have only been checked in tests. On a phone: take 10 screenshots during a session, flick through them, name a few, undo once, and open the album.

## Open items
- Session 5: Albums, Triage and Album are real. Editor (session 6), Export (session 7) and Settings (session 9) still show fixed content. Export says "19 screens, 10 pins" and "2 redactions" whatever the album holds.
- Session 3: `Shot.width` and `height` are optional because reading them needs an image decode; the capture plugin should supply them.
- Session 3: deleting a pin renumbers the rest, so pin numbers in an exported Claude pack can change between exports. Fine for now; revisit if pins need stable IDs in exports.
- Session 3: no migration beyond v1 exists, so the first real migration is untested. Test it when one is added.
- Session 4: capture is unverified on a device. Risks to check first: (1) the name and folder heuristic on your phone's brand; (2) whether the foreground service survives the app being swiped away and the phone idling; (3) Android 14 "selected photos" handling; (4) the "watching" notification and its icon (it reuses the launcher icon, so it is a grey square on some versions: needs a proper monochrome icon).
- Session 4: a new album starts a session in it, and starting one ends the previous. There is no UI to choose another album for an existing session or to end a session; only Pause and Resume. Decide in session 5.
- Session 4: a crash between storing a shot and acking its inbox file would import that screenshot twice. The window is tiny; add a source id column if it ever shows up.
- Session 4: screenshots taken while paused, or with no session, are dropped (originals stay in the gallery). Intended.
- Session 4: the watcher does not restart after a reboot. The session survives in the database and sync resumes watching the next time the app opens.
- Session 4 (release, session 10): the service uses the `specialUse` foreground type. Google Play needs a declaration and a justification for it in the Play Console. The manifest property text is a draft. Also the debug build has the INTERNET permission (Flutter hot reload); confirm the release build has none, to back the local-only claim.
- Session 5: Flow order is capture order. There is no way to reorder screens yet (mocks do not show one). When it is built it needs buttons as well as drag (WCAG 2.5.7), see the item below.
- Session 5: tapping a tile opens the static Editor, not the tapped screen, until session 6.
- Session 5: Done in Triage leaves unsorted shots pending (they stay in "Review N new"). Discarded shots are kept in the database and their files stay on disk; there is no "Discarded" view and no purge yet. Decide whether discards should delete the file.
- Session 5: filter chips count screens that have at least one pin of that severity, not pins. The mock does not say which.
- Session 5: on the album screen the filter chips wrap to a second line on narrow phones instead of scrolling, because a half-visible chip is easy to miss.
- Session 5: the Triage card shows the whole screenshot (letterboxed), not a crop, so nothing is hidden while reviewing.
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
- 2026-11-09: Session 5 triage and album. Triage (Keep, Discard, Undo, names, flick with button and TalkBack alternatives) and the Album screen (Grid, Flow order, severity filters, real thumbnails) read and write the database. 100 tests, including a 10-shot session sorted into an album. Fixed a false "Needs photo access" flash on the session card.
