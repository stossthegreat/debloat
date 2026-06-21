# ImHim — Per-user Unit Economics

Quick reference. Numbers as of June 2026. All voice cost assumes `gpt-4o-mini-realtime` (the AURALAY backend default). Store cut assumed at 15% (Apple Small Business Program / Google Play first $1M tier).

---

## Per-user weekly cost — Pro tier caps

**Voice (Free Flow / Council) — `gpt-4o-mini-realtime`**
- Cap: 18 min/wk
- Cost: ~$0.05/min blended (40% user / 60% AI mix)
- Heavy use (cap maxed): $0.90/wk
- Average use (~5 min/wk): $0.25/wk

**Mirror renders — Replicate (Nano Banana + face-swap)**
- Cap: 3/wk
- Cost: ~$0.015 each
- Heavy: $0.045/wk
- Average (1/wk): $0.015/wk

**Rizz screenshot replies — `gpt-4o-mini` vision**
- Cap: 15/wk
- Cost: ~$0.003 each
- Heavy: $0.045/wk
- Average (3/wk): $0.009/wk

**Scans — `gpt-4o` vision honest-looks rating**
- Cap: 2/wk
- Cost: ~$0.02 each
- Heavy: $0.04/wk
- Average (1/wk): $0.02/wk

**Backend hosting (Railway)**
- ~$0.01/wk per active user (rounding error)

**TOTAL per-user weekly cost**
- Heavy user (all caps maxed): **~$1.04/wk**
- Average user: **~$0.30/wk**

---

## Revenue per Pro user (after 15% store cut)

**Weekly tier $6.99/wk**
- After Apple/Google cut: **$5.94/wk**

**Annual tier $109.99/yr**
- $109.99/yr × 0.85 = $93.49/yr
- Per week amortised: **$1.80/wk**

---

## Net margin per user

**Weekly $6.99 tier**
- Heavy user: $5.94 − $1.04 = **+$4.90/wk (82% margin)**
- Average user: $5.94 − $0.30 = **+$5.64/wk (95% margin)**

**Annual $109.99 tier**
- Heavy user: $1.80 − $1.04 = **+$0.76/wk (42% margin)**
- Average user: $1.80 − $0.30 = **+$1.50/wk (83% margin)**

---

## Per-year profit per Pro user (15% cut)

**Weekly subscriber (heavy):** $4.90 × 52 = **$254.80/yr**
**Weekly subscriber (avg):** $5.64 × 52 = **$293.28/yr**
**Annual subscriber (heavy):** $0.76 × 52 = **$39.52/yr**
**Annual subscriber (avg):** $1.50 × 52 = **$78.00/yr**

---

## Cost levers

Voice is **96% of the heavy-user cost** ($0.90 of $1.04). Every other cap combined is $0.13/wk worst case.

Implications:
- Voice cap above ~25 min/wk on annual without a price raise = annual heavy users bleed.
- Renders / rizz / scans caps can move up generously with negligible cost impact (could give 5 renders, 30 screenshots, 3 scans per week without moving the needle).
- The Sunday → Monday rollover bleed (v278 fix) was costing ~$0.90/wk per exploiter on doubled voice. Now closed by the per-user rolling 7-day window.

---

## What the unit economics are NOT modelling

- App Store / Play Store paid acquisition cost (CAC). Subtract whatever blended CAC you're paying for installs.
- Refunds and chargebacks. Industry standard ~3-5% of revenue.
- 30% store cut (vs 15%) after Year 2 of Apple SBP or after Play's $1M/year threshold. At 30% cut, divide all revenue lines by 0.85 / 0.70 ≈ 18% drop. Heavy annual margin gets thin (~$0.45/wk) but stays positive.
- Voice cost variation. The $0.05/min blended assumes typical 40/60 user/AI mix; a chatty AI persona or longer responses push it up. Worst observed cost ceiling is around $0.08/min for very AI-heavy convos — heavy weekly margin still positive at that ceiling.
- Backend egress. Railway charges for outbound bandwidth; bytes/user/wk is small but if usage spikes (concurrent voice sessions globally) add ~5-10% buffer to backend cost.

---

## TL;DR

Unit economics are healthy at current caps with mini-realtime. No tier bleeds. Voice is the only variable worth watching. Don't raise voice caps without raising prices or splitting tiers.
