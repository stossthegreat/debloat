# Onboarding reel assets

Visuals for the cinematic intro reel (`lib/screens/onboarding/intro_reel_screen.dart`).
Drop these four files in this folder with these EXACT names — the reel already
references them, no code change needed. Until they're added, each screen shows
a clean play-icon placeholder, so the build never breaks.

| File            | Screen | What it should show |
|-----------------|--------|---------------------|
| `looks.jpg`     | 4 · LOOKS    | AI glow-up: current → future (before/after slider or split) |
| `game.jpg`      | 5 · GAME     | Live roleplay UI — the AI conversation orb / chat |
| `messages.jpg`  | 6 · MESSAGES | A dead conversation being rewritten into a strong reply |
| `future.jpg`    | 7 · FUTURE   | A confident, aspirational still (kept tasteful) |

### Specs
- **Aspect ratio:** portrait-ish, ~4:5 or 3:4. The reel caps height at ~30% of
  the screen and crops with `BoxFit.cover`, so center the subject.
- **Format:** JPEG, sRGB, ~80% quality. ~150–250 KB each.
- **Keep it App-Store-safe:** no sexualized imagery, no cleavage/suggestive
  poses, no "get dates / tonight" overlay text. Apple flagged the store
  screenshots under Guideline 1.1 — keep these clean (self-improvement,
  confidence, grooming, clean UI) so the in-app reel doesn't reintroduce the
  same problem for a reviewer running the app.
