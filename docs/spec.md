# Fluo spec

## What it is
A fast capture-to-share loop for screenshots. Take a screenshot on the phone; it lands in a review session; keep or discard it; name the screen; annotate; group into an album; export.

## v1 scope
- Albums list, with an active session card and "Review N new".
- Triage: card stack, Keep or Discard (buttons and flick), Undo, screen name field.
- Album: Grid and Flow order views, severity filter chips, flow numbers, pin badges.
- Editor: crop, pen, arrow, box, numbered pins with severity and note, redact or blur, caption.
- Export: Claude pack, PDF, long image, share images; switches for original screenshots and review brief; redaction notice.
- Settings: colour theme, auto-update (Wi-Fi only option), version and check for updates.
- Local storage only.

## v2 candidates
Review-prompt preface, contrast eyedropper and touch-target ruler, OCR in export, before/after compare, voice captions.

## Non-goals
Accounts, cloud sync, collaboration, web version, screen recording.

## Accessibility floor
WCAG AA contrast, 44dp touch targets, every gesture has a tap alternative (WCAG 2.5.1, 2.5.7), reduced-motion support, TalkBack custom actions, visible focus.
