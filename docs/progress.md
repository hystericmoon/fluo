Last updated 2026-11-09

## Next up
Session 3: Data layer (see docs/plan.md). Album, screenshot, pin and edit models, SQLite plus a file store.

Still owed from sessions 1 and 2: run on a physical Android device (`flutter run`) and eyeball every screen next to refs/mocks. Nothing has been run on real hardware yet.

## Open items
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
