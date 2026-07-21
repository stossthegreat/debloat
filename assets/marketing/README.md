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

The paywall's BODY slide (panel 2) uses:

```
assets/marketing/body_beforeafter.jpg   ← BUNDLED (b377)
```

It is the founder-supplied Body-tab verdict composition: before/after
pair (skinny left, committed one-year physique right, same man) with
the NOW / COMMITTED labels, the 62 → +28 → 90 score strip and the
verdict line ALL baked into the image. The slide renders it 1:1 with
no overlays. Normalised to **914 × 778** — the exact crop of
beforeafter.jpg, so both slides present at the same size.

To replace it, drop a new JPEG at the same path with the same 914×778
crop (resize to width 914, trim overshoot off the top). Same man in
both halves — Apple flags fake before/after marketing under
guideline 4.2 / 5.0.
