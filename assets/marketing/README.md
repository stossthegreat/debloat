## Mirrorly marketing assets — Mirror-tab before/after

The Mirror-tab pre-scan stack expects **two** JPEGs:

```
assets/marketing/before.jpg
assets/marketing/after.jpg
```

Drop the files here with those exact names. The Flutter side already
references them — no pubspec edits, no code edits. Replace, build,
done.

### Specs
- **Aspect ratio:** 4:5 portrait (e.g. 800 × 1000 px). The tile crops
  to 4:5, so anything else letterboxes.
- **Format:** JPEG, sRGB, ~80% quality. ~150 KB each is plenty.
- **Same face:** the BEFORE and AFTER must be the same person. Apple
  flags fake before/after marketing under guideline 4.2 / 5.0.
- **Lighting:** match before & after. Same angle, same light, same
  background. The only thing that should change is the transformation.

### Fallback
If either file is missing the tile renders a placeholder face icon —
the build still ships, the Mirror tab still loads. Drop the JPEGs
whenever they're ready.

---

## Paywall BODY panel — body before/after

The paywall's BODY slide (panel 2) expects **one** JPEG:

```
assets/marketing/body_beforeafter.jpg
```

A single side-by-side pair: skinny/untrained on the LEFT, the
committed one-year physique on the RIGHT — same man, same pose, same
light (like the Body tab's result card). The slide overlays its own
NOW / COMMITTED labels and the 62 → 90 scores, so the image itself
should carry NO text.

### Specs
- **Aspect ratio:** 914 × 778 (same crop as beforeafter.jpg — the
  slide crops to it, anything else letterboxes).
- **Format:** JPEG, sRGB, ~80% quality.
- **Same man both halves** — Apple flags fake before/after marketing
  under guideline 4.2 / 5.0.

### Fallback
If the file is missing the slide shows a dark placeholder with a
dumbbell icon — the build still ships. Drop the JPEG whenever it's
ready (marketing dir auto-bundles, no pubspec edit).
