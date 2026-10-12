# Pasa — Icon Composer Assets

Layered SVG assets for Apple's Icon Composer (`.icon` format, iOS 26+ SDK).
Two concepts, each with a **background** layer and a **foreground** (glyph) layer,
in light and dark appearances.

```
IconAssets/
├── TallyBowl/            ← recommended concept
│   ├── background-light.svg
│   ├── background-dark.svg
│   ├── foreground-light.svg   (bowl + tally strokes, no strike)
│   ├── foreground-dark.svg
│   ├── strike-light.svg      (separate layer — recolor per appearance)
│   └── strike-dark.svg
├── RingBowl/
│   ├── background-light.svg
│   ├── background-dark.svg
│   ├── foreground-light.svg
│   └── foreground-dark.svg
└── README.md
```

## Building the .icon

1. Open **Icon Composer** (ships with Xcode 26; also downloadable from developer.apple.com).
2. Create a new icon. Two layers appear: **Background** and **Foreground**.
3. Drag `background-light.svg` into the Background layer's **Light** well,
   and `background-dark.svg` into its **Dark** well.
4. Drag `foreground-light.svg` / `foreground-dark.svg` into the Foreground layer the same way.
5. **Tally Bowl only:** add a third layer for the strike — import `strike-light.svg`
   (and `strike-dark.svg`) as its own layer above the foreground. This lets you set
   Default/Dark/Mono fills on the strike independently in the inspector.
6. **Tinted** appearance is generated automatically from the layers — preview it in the
   tinted tab; customize later only if the auto render loses the glyph.
7. Preview at all sizes (especially 60 pt / notification size) and in dark + tinted modes.
8. Save the `.icon` file, then drop it into the app's asset catalog
   (e.g. `pasa/Assets.xcassets`). Legacy PNG sizes for older iOS versions
   are generated automatically from the `.icon`.

## Design notes

- Canvas is 1024×1024; do **not** pre-round corners — the system applies the mask.
- Foreground glyphs sit inside ~50–60% of the canvas with clear margins, which is
  where Icon Composer's glass/specular treatment looks best.
- Palette: terracotta `#E85D3D`, deep green `#2D6A4F`, cream `#FDF3E3`,
  charcoal `#1C1B18`–`#26231E` (dark backgrounds).
- Solid fills and round line caps only — no filters or blur, so the SVG layers
  render identically in Icon Composer and in any vector tool.
- To tweak: open any SVG in a text editor; geometry is plain paths and circles.

## Concept legend

- **Tally Bowl** — steam strokes double as tally marks, struck through in terracotta.
  Reads as "bowl with steam" at 60 px, "tally" at full size. Most ownable.
- **Ring & Bowl** — 270° progress ring (gap at top for steam) around a bowl.
  Instantly reads as a nutrition/tracking app. Safest option.
