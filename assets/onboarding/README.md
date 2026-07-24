# Onboarding funnel image assets

Status after bro's first art drop (v1.0.0+27):

## ✅ RECEIVED — live in the app
- `assets/marketing/before.jpg`      — bloated face (1080×1440)
- `assets/marketing/after.jpg`       — drained face (1080×1440)
- `assets/marketing/beforeafter.jpg` — composited split, bloated LEFT /
                                       drained RIGHT, seam dead-centre
                                       (paywall hero draws its violet
                                       beam exactly there) (1096×932)
- `welcome_food.jpg`                 — plate shot; onboarding overlays
                                       the sodium callout lines + verdict
                                       chip in code (1080×1080)
- `welcome_routine.jpg`              — gua sha + roller (1080×1080)

Slide 1 of the welcome carousel no longer uses a static image — it's
the interactive BeforeAfterSlider over before.jpg/after.jpg, divider
starting at exactly 50%.

## 🔜 STILL WANTED (placeholders show until they land)
- `welcome_scan.jpg`  — 4:5 (~1080×1350) .jpg — marble Greek bust, 3/4
                        profile, glowing violet wireframe face-mesh.
                        (Currently unused on slide 1 since the slider
                        took over, but wired as its fallback and usable
                        elsewhere.)
- `gender_male.png`   — 3:4 (~900×1200) .png — male model, neutral top,
                        calm studio, cut-out fading at base.
- `gender_female.png` — 3:4 (~900×1200) .png — female model, same
                        treatment.

Drop files into this folder (or assets/marketing/ for the pair) with
these EXACT names — they auto-bundle on the next build, no code edit.
Nothing here blocks a build; every slot has a clean violet placeholder.
