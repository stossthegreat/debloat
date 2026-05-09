## Mirrorly marketing assets — before/after thumbnails

The Mirror-tab pre-scan stack expects six JPEGs at the exact paths and
ratios below. Drop them in this folder using the names listed; the
Flutter side already references these paths in `pubspec.yaml` and in
`lib/screens/home/home_screen.dart`. No code change needed — replace
the file, hot-restart, done.

| Slot     | Path                                       | Notes                                          |
|----------|--------------------------------------------|------------------------------------------------|
| HAIR     | `assets/marketing/hair-before.jpg`         | Same face, plain / current cut                 |
|          | `assets/marketing/hair-after.jpg`          | Same face, recommended cut applied             |
| BEARD    | `assets/marketing/beard-before.jpg`        | Same face, clean / current state               |
|          | `assets/marketing/beard-after.jpg`         | Same face, recommended beard applied           |
| FRAMES   | `assets/marketing/frames-before.jpg`       | Same face, no glasses                          |
|          | `assets/marketing/frames-after.jpg`        | Same face, recommended frames applied          |

### Specs
- **Aspect ratio:** 4:5 portrait (e.g. 800 × 1000 px). The thumbnail
  in the UI crops to 4:5 — anything else will get letterboxed.
- **Format:** JPEG, sRGB, ~80% quality. ~150 KB each is plenty.
- **Faces:** the BEFORE and AFTER must be the same person. Apple
  flags fake before/after marketing under guideline 4.2 / 5.0.
- **Lighting:** match before & after. Same angle, same light, same
  background. Differences should be the change (cut, beard, frames),
  nothing else.

### What we're using right now
While the real assets aren't in place, the Mirror tab falls back to
a tasteful placeholder block (no broken-image icon) so the build
won't break. Drop the six JPEGs in this folder and the stack lights
up automatically.
