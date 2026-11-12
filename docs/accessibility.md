# Accessibility

The floor (from `docs/spec.md`): WCAG AA contrast, 44dp touch targets, every gesture has a tap alternative (WCAG 2.5.1, 2.5.7), reduced-motion support, TalkBack custom actions, visible focus.

## What is checked automatically

| Check | Where | What it proves |
|---|---|---|
| Contrast of every colour pair the app draws | `test/contrast_test.dart`, `lib/theme/contrast.dart` | Text pairs are at least 4.5:1, control boundaries and icons at least 3:1. The warning notice border was raised from #7A5C10 to #8A6A14 to pass. |
| 44dp targets | `smallTargets` in `test/support/harness.dart`, used by most screen tests and `test/accessibility_test.dart` | No tappable node is smaller than 44x44dp, in every state of every screen. |
| Every control has a name | `unlabeledControls`, `test/accessibility_test.dart` | No tap target, toggle or text field reaches a screen reader without a label. |
| Gesture alternatives | `test/accessibility_test.dart`, `test/delete_reorder_test.dart`, `test/editor_screen_test.dart`, `test/motion_test.dart` | See the table below. |
| Large text | `test/text_scale_test.dart` | At 130% and 200% system text, every control keeps a name and a 44dp target. (Overflow errors cannot be used here: shadcn_flutter has its own Row and Column that do not raise them.) |
| Reduced motion | `test/motion_test.dart` and the Triage, Editor and Albums tests | With the system "remove animations" setting or the in-app switch, nothing animates, and nothing depends on an animation to be understood. |
| Keyboard | `test/accessibility_test.dart` | Tab moves through controls, Enter activates one, a focused control shows a 2dp lime ring. |
| Semantics structure | `test/editor_screen_test.dart` | Containers that hold controls use `explicitChildNodes: true`, so each control is its own node. |

## Gestures and their alternatives

| Gesture | Alternative without a gesture |
|---|---|
| Flick a card in Triage (right keeps, left discards) | Keep and Discard buttons; Undo button; "Keep" and "Discard" custom actions on the card |
| Swipe an album row to delete | "Delete album" custom action on the row; "Hold to delete album" inside the album. Both lead to the same Undo bar |
| Hold a button to confirm (Hold to delete) | Tap once to arm, tap again to confirm. Keyboard Enter and screen reader double tap take this route |
| Drag screens to reorder (not built; reorder is buttons only) | "Reorder screens" mode with Move earlier / Move later buttons on each tile; "Move earlier" and "Move later" custom actions on each tile |
| Tap the image to place a pin | "Add pin in the middle", then move it with four arrow buttons |
| Drag a pin | Arrow buttons ("Move pin left" and so on) |
| Drag to draw a box, arrow or redaction | "Add a box / an arrow / a redaction in the middle", then Move (four arrows) and Wider, Narrower, Taller, Shorter (Longer, Shorter for an arrow) |
| Tap a mark on the image to select it | The "Marks on this screen" list: every mark is a button |
| Drag crop corners or the frame | Eight custom actions on the crop frame ("Trim more from the left", "Trim less from the top", and so on, in 5% steps) |
| Shift or Cmd click to select several screens (desktop) | The **Select** button (clicks then toggle), **Select all** button, Space toggles the focused screen, Cmd+A. Tiles announce "selected". |
| Double click a screen to edit it (desktop) | The **Edit marks** button in the inspector, or Enter. |
| Keyboard shortcuts (desktop: K/D/arrows in Triage; arrows, Space, Enter, Delete, G, F, R in the album) | Every one has a button on screen. Single keys do nothing while a text field has focus. |
| Draw a freehand pen stroke | **None.** A freehand line is inherently a finger gesture. A box or an arrow does the same job with buttons. The editor says "Draw on the screenshot with your finger." |

## Time limits

The undo bar after deleting an album burns for 6 seconds. With a screen reader or switch access on (`accessibleNavigation`) it lasts three times as long (WCAG 2.2.1). The delete is not final until it burns; leaving the screen before then keeps the album.

## Reduced motion

`reducedMotion(context)` is true when the system "remove animations" setting is on or the in-app switch is on (`MotionScope`). Then:
- route fades, the Triage card entrance and the card fly-out are skipped;
- the Hold Button has no filling bar (the hold is still required: it says "Keep holding…");
- the Swipe Row commits without sliding;
- the undo bar shows a countdown in words ("Deleted Checkout (6 s)") instead of a burning line;
- the live border on the session card is a still border;
- the crop frame appears in place.

## Manual TalkBack script (needs a phone)

Turn on TalkBack and go through this once. Each line should work without looking at the screen.

1. **Albums.** Swipe right through the screen. You should hear: Albums (heading), Settings, New album, then the session card ("Active session"), its buttons, then each album as one item with its name and screen count. On an album row, open the Actions menu: "Delete album" is there.
2. **New album.** Activate New album. The dialog is announced as "New album". The name field is announced with its label. Create and Cancel are reachable.
3. **Session card.** Each state is read in words (Session on / Session paused / Needs photo access). The fix button is the only action when access is missing.
4. **Triage.** Focus the card: Actions menu offers Keep and Discard. Keep and Discard buttons work. After the last one, "All sorted" is announced.
5. **Album.** Each tile reads "Screen 2: Cart, 2 pins: Bug, UX". Actions menu: Move earlier / Move later. "Reorder screens" toggles the move buttons. "Hold to delete album" says "Hold to confirm. Or tap twice."; double tap, then double tap again.
6. **Delete and Undo.** After deleting, you hear "Deleted <name>"; Undo is the next item and works.
7. **Editor.** Switch tools. With Pin: "Add pin in the middle", then Move pin buttons. With Redact: "Add a redaction in the middle", then the move and size buttons. Open the Marks list and select a mark. Crop: Actions menu on "Crop frame" lists eight trim actions.
8. **Export.** Format cards read as a radio group with one selected. Switches say on or off. The redaction notice is read when it changes (turn originals on and off). "Exporting 3 of 19…" is read as progress.
9. **Large text.** In system settings set font size to the largest. Open each screen: nothing is cut off and every button is still reachable.
10. **Remove animations.** Turn it on. The session card border stops moving; deleting shows "(6 s)" instead of a burning line.

## Known limits

- Freehand pen strokes need a finger (see above).
- The PDF export uses the bundled Lexend font; other scripts show as empty boxes in the PDF only.
- Nothing here replaces a real TalkBack pass; the automated checks cover structure, names, sizes and alternatives, not how it sounds.
