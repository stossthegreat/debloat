# Onboarding funnel image assets

Drop the generated images here with these **EXACT** filenames — the funnel
references them by name. Until a file lands, that spot shows a clean,
on-brand violet placeholder tile (a line-icon + "IMAGE COMING" caption),
**not** an emoji. The moment you drop the real file in this folder it
auto-bundles on the next build — no code or pubspec edit needed.

## Welcome carousel — 3 images (4:5 portrait, ~1080×1350, .jpg)
These are the first 3 hero screens. Full-bleed, dark violet-black mood so
they blend into the funnel background.

- **welcome_scan.jpg**    — marble Greek bust, 3/4 profile, glowing violet
                            wireframe face-mesh with sparkle nodes. Sells
                            "Face Scan".
- **welcome_food.jpg**    — clean overhead meal shot (grilled salmon,
                            greens, avocado — real food, appetising, bright
                            against dark). Sells "Food Analysis".
- **welcome_routine.jpg** — rose-quartz gua sha + jade face roller, water
                            droplets, soft violet light. Sells "Daily
                            Routines".

## Gender select — 2 images (3:4 portrait, ~900×1200, .png)
Shown side-by-side on the "who you are" screen. Ideally cut-out subjects
fading to transparent at the base so they sit on the card cleanly.

- **gender_male.png**     — male model, neutral top, calm studio light.
- **gender_female.png**   — female model, neutral top, calm studio light.

## Also used by onboarding (already referenced elsewhere)
The shock-stat + identity-fork screens reuse the marketing before/after art
from `assets/marketing/`:

- **assets/marketing/beforeafter.jpg** — single combined bloated→debloated
                            image, split baked in (~914×778). Also the
                            paywall hero.
- **assets/marketing/before.jpg**      — bloated face, 3:4 portrait.
- **assets/marketing/after.jpg**       — same face debloated, 3:4 portrait.

---
**Nothing here blocks the build.** Every reference has a placeholder
fallback, so you can ship or TestFlight without these and drop the real art
in whenever it's ready.
