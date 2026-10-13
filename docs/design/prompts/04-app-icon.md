Design the app icon for XPath, a Mac app (open source, free) for teams that build Flutter apps. It takes an app from code on a branch to live in the App Store and Google Play: it builds, tests, signs, uploads, waits for Apple and Google to approve, then merges the release. Under the hood it is a pipeline: work flows through stages, splits into parallel jobs on different machines (a Mac for iOS, a Linux box for Android), and joins again at the release. The feeling is "Xcode meets Railway meets GitHub Actions": precise, calm, native to the Mac, a tool engineers trust with production.

The name is XPath: X as in cross-platform (iOS and Android) and the crossing point where parallel paths meet; Path as in the route a release takes from commit to store.

## The visual language it must belong to

The app's design system is called **Run Sheet**: ink on paper. Warm off-white paper, near-black ink, hairline rules, labels in monospace caps (IBM Plex Mono), no shadows, no gradients, no decorative colour. Colour is spent only on state, and one blue accent marks the single primary action. The pipeline in the app is drawn as nodes joined by 1.5 px wires: solid once a stage has run, dashed while not yet reached. The icon should feel like it was drawn with the same pen.

## Colours (use only these)

| Role | Light appearance | Dark appearance |
|---|---|---|
| Background (paper) | `#F6F5F1` (window), may lift to `#FBFAF7` | `#141412`, may lift to `#1E1E1B` |
| Symbol (ink) | `#1B1B18` | `#ECEAE3` |
| Accent (one element at most) | `#2449B8` | `#7EA2FF` |
| Hairline, if any | `#E3E1DA` | `#33322D` |

The accent is for one small thing only (the node where the paths meet, or the end of the route), never a fill behind the symbol. A very subtle tonal shift within the paper (for example `#FBFAF7` to `#EFEEE8`) is acceptable for depth; no colourful gradients. Do not use the status colours (green `#1E7A4C`, amber `#F0B44C`, red `#B42318`, purple `#4B2FA0`); they mean things inside the app.

## Step 1: concepts (then STOP)

Give me 8 symbol concepts as clean flat drawings, ink on paper with at most the one accent, each with a one-line idea. Push for range, for example:
- two paths (iOS and Android) that run in parallel and cross to form an X, with an accent node at the crossing;
- a pipeline: one wire that splits into two and rejoins at a single accent node;
- an X built from two route segments, one solid and one dashed (run vs not yet reached);
- a path of three or four nodes (stages) ending in a confident terminal point;
- a monogram where the X and a path or arrow share strokes, drawn with the wire weight;
- a run-sheet idea: an X set like a mark on a ledger or checklist;
- something unexpected that still reads as "route" or "release".

Avoid: rockets, ships, planes, gears, wrenches, play buttons, checkmark-only marks, the Flutter logo or Dart arrow, Apple or Google logos, literal phones, letters other than X, glossy 3D, text.

For each concept, show it at 1024 px and at 32 px side by side, in light and dark, so I can see whether it survives small. Then stop and let me choose.

## Step 2: final icon (after I choose)

The symbol only, centred, taking up about 60% of the canvas, on the paper background. 1024×1024, no text, no border, no rounded corners and no drop shadow (macOS applies the squircle mask and its own depth).

Deliver it in layers for Apple's Icon Composer: a background layer (paper) and one or two foreground layers (ink symbol, accent element), so macOS can render the default, dark, clear and tinted appearances. Provide the dark appearance explicitly with the dark colours above.

### It must also work

- Small: recognisable at 16×16 and 32×32 px in Finder, the Dock and Spotlight. Stroke weights must hold at that size; thicken them for the small renders if needed rather than letting dashed segments disappear.
- In one colour: a single-colour symbol on transparent for the tinted and clear appearances, the menu bar extra (template image at 18 pt, pure black on transparent, readable at 16 px), and the 20 px slot at the top of the app's sidebar.
- Dark: works on `#141412` without losing the symbol.
- Square crops: a 512×512 version on the paper background for the GitHub social preview, and a favicon at 32×32.
