# Plan

1. **Scaffold.** Flutter project, `shadcn_flutter` at its latest version, dark lime theme tokens, Lexend wordmark, splash and icon. Done when the app runs on an Android device with the splash and an empty Albums screen.
2. **Static screens.** The six core screens built from `refs/mocks/` with fake data. Done when each matches its mock at 390 wide and every target is at least 44dp.
3. **Data layer.** Album, screenshot, pin and edit models, SQLite plus a file store. Done when albums and screenshots survive an app restart.
4. **Android capture.** Kotlin plugin detects new screenshots and feeds the active session. Done when a real screenshot appears in "Review N new" within a second or two.
5. **Triage and album.** Working Keep, Discard, Undo, screen names, Grid, Flow order and filters. Done when a 10-shot session can be sorted into an album.
6. **Editor.** Crop, pen, arrow, box, pins with severity, redact, captions, all as vector data. Done when edits reopen unchanged and the original file is untouched.
7. **Exporters.** Claude pack, PDF, long image, share. Done when redacted areas are solid in every export and originals are excluded by default.
8. **Motion and access.** Motion kit, reduced-motion, tap alternatives, a button alternative for reordering, TalkBack actions. Done when the TalkBack pass has no unreachable action.
9. **Settings and updates.** Colour themes, auto-update mechanism (decide: Play in-app updates or release check), version display. Done when a theme change applies across all screens.
10. **Release checks.** Fluo trademark, domain and store availability; React Bits license; signing; store listing; Play declaration for the `specialUse` foreground service; confirm the release build has no INTERNET permission; font (OFL) licences. Done when each item is written down as cleared or changed.
