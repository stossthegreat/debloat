# Lucien — character render

ONE file covers every Lucien role for now (hero, voice turns, feedback
strip). Drop a single image at the path below and it appears across
the Game tab, the Eyes Part 2 voice screen, and the feedback strip.

| File | Used by | Brief |
|---|---|---|
| `lucien.jpg` | Game masthead, Eyes Part 2, "Lucien's Feedback" strip | Dark suit, leather chair, dim red-lit room. Eyes camera-direct. Danger-calm. |

Format: JPEG, **square** (1:1), 1500 × 1500 px, sRGB, ~85% quality, ≤ 400 KB.

Art direction:
- Pure black or very dim interior background
- Single warm-red rim light
- Eyes always engaged with camera
- Photoreal, cinematic, 50–85 mm lens feel
- Mid-30s to early-40s, sharp features, controlled

When you have dedicated **speaking** and **feedback** variants later,
add `speaking.jpg` and `feedback.jpg` and update the two constants in
`lib/widgets/common/mirrorly_components.dart → MirrorlyAssets`. The
rest of the code keeps working unchanged.
