Last updated 2026-11-09

## Next up
Session 4: Android capture. Kotlin plugin detects new screenshots and feeds the active session (see docs/plan.md). It should call `FluoRepo.addShot`, which already copies the file in as a pending shot.

Still owed from sessions 1 to 3: run on a physical Android device (`flutter run`). Nothing has run on real hardware. On a device, check that an album created with New album is still there after force-closing the app.

## Open items
- Session 3: only the Albums list is real (reads the database, New album works). Album, Triage, Editor and Export still show fake data and need wiring: Triage and Album in session 5, Editor in session 6, Export in session 7.
- Session 3: there is no "session" row yet. The Albums session card shows when any album has pending shots and points at the first one. Session 4 or 5 needs a real active-session concept (which album new screenshots go to, paused or not).
- Session 3: `Shot.width` and `height` are optional because reading them needs an image decode; the capture plugin should supply them.
- Session 3: deleting a pin renumbers the rest, so pin numbers in an exported Claude pack can change between exports. Fine for now; revisit if pins need stable IDs in exports.
- Session 3: no migration beyond v1 exists, so the first real migration is untested. Test it when one is added.
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
