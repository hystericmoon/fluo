Last updated 2026-11-09

## Next up
Session 2: Static screens (see docs/plan.md). Build the six core screens from refs/mocks with fake data.

Session 1 is code-complete but not yet run on a physical Android device (none in the build container). Do that check first: `flutter run`, confirm splash then empty Albums, and that the Lucide icons render.

## Open items
- Session 1: Settings button border uses `borderStrong` (#6B6B76). Re-check the other shadcn outline controls against the 3:1 floor in session 2.
- No button alternative for drag-reorder yet (session 8).
- Check Fluo trademark, domain and store names (session 10).
- Check the React Bits license before porting anything (session 10).
- Auto-update mechanism not decided.

## History
- 2026-11-09: Kickoff. Name Fluo, FLUO Lexend wordmark, stacked icon, seven mocks done.
- 2026-11-09: Session 1 scaffold. Flutter project, shadcn_flutter 0.0.55, dark lime theme, bundled Lexend and Inter, wordmark, icon, splash, empty Albums. analyze and test pass, debug APK builds.
