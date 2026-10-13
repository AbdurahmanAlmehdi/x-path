Design the app icon for XPath, a Mac app (open source, free) for teams that build Flutter apps. It takes an app from code on a branch to live in the App Store and Google Play: it builds, tests, signs, uploads, waits for Apple and Google to approve, then merges the release. Under the hood it is a pipeline: work flows through stages, splits into parallel jobs on different machines (a Mac for iOS, a Linux box for Android), and joins again at the release. The feeling is "Xcode meets Railway meets GitHub Actions": precise, calm, native to the Mac, a tool engineers trust with production.

The name is XPath: X as in cross-platform (iOS and Android) and the crossing point where parallel paths meet; Path as in the route a release takes from commit to store.

Colours: use the palette from the XPath design system: [paste accent, surface and status colours from tokens.json]. The background is [token] and the symbol is [token]; one accent at most.

## Step 1: concepts (then STOP)

Give me 8 symbol concepts as clean flat sketches on the background colour, each with a one-line idea. Push for range, for example:
- two paths (iOS and Android) that run in parallel and cross to form an X;
- a pipeline: one line that splits into two and rejoins at a single point;
- an X built from two track or route segments with a node where they meet;
- a path drawn as connected nodes (stages) ending in a confident terminal point;
- a monogram where the X and a path or arrow share strokes;
- something unexpected that still reads as "route" or "release".

Avoid: rockets, ships, planes, gears, wrenches, play buttons, checkmark-only marks, the Flutter logo or Dart arrow, Apple or Google logos, literal phones, letters other than X, gradient washes, glossy 3D, text.

For each concept, show it at 1024 px and at 32 px side by side so I can see whether it survives small. Then stop and let me choose.

## Step 2: final icon (after I choose)

The symbol only, centred, taking up about 60% of the canvas, on the background. 1024×1024, no text, no border, no rounded corners and no drop shadow (macOS applies the squircle mask and its own depth).

Deliver it in layers for Apple's Icon Composer: a background layer and one or two foreground layers for the symbol, so macOS can render the default, dark, clear and tinted appearances.

### It must also work

- Small: recognisable at 16×16 and 32×32 px in Finder, the Dock and Spotlight.
- In one colour: a single-colour symbol on transparent for the tinted and clear appearances, the menu bar extra (as a template image at 18 pt, pure black on transparent, readable at 16 px), and in-app use in the sidebar.
- Dark: works on the dark appearance without losing the symbol against the background.
- Square crops: also give a 512×512 version on the background for the GitHub social preview and a favicon at 32×32.
