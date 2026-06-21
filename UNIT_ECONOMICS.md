# ImHim — Unit Economics

What every Pro user costs us per week, and what we earn after Apple / Google take their cut.

> **The bottom line:**
> Both Weekly and Annual tiers are profitable at current caps, on both heavy users and average users. The one cost lever worth watching is voice. Don't raise the voice cap above ~25 min/wk without raising the price.

---

## The Assumptions

- Voice cost based on `gpt-4o-mini-realtime` (the AURALAY backend default).
- Store cut at **15%** — Apple Small Business Program / Google Play first-$1M/yr tier.
- Replicate render cost ~$0.015 per image (Google Nano Banana + face-swap post-pass).
- gpt-4o-mini for screenshot rizz ($0.15 / $0.60 per 1M tokens) after the v265 cost swap.
- All numbers in USD. Numbers as of June 2026.

---

## Per-user Weekly Cost

Pro caps are 18 voice min, 3 Mirror renders, 15 rizz screenshots, 2 scans, per rolling 7-day window (v278 — anchored per user, no global Monday rollover).

| Feature | Cap / wk | Unit cost | Heavy use (cap maxed) | Average use |
|---|---|---|---|---|
| Voice (Free Flow / Council) | 18 min | ~$0.05 / min* | **$0.90** | ~$0.25 (5 min/wk) |
| Mirror renders | 3 | ~$0.015 each | **$0.045** | ~$0.015 (1/wk) |
| Rizz screenshot replies | 15 | ~$0.003 each | **$0.045** | ~$0.009 (3/wk) |
| Honest-looks scans | 2 | ~$0.02 each | **$0.04** | ~$0.02 (1/wk) |
| Railway backend | — | rounding error | **~$0.01** | ~$0.01 |
| **Total** | — | — | **~$1.04 / wk** | **~$0.30 / wk** |

\* gpt-4o-mini-realtime: $10/M input audio + $20/M output audio. Typical Free Flow ratio is ~40% user / 60% AI talking, blends to ~$0.05/min.

---

## Revenue Per User

After the 15% store cut.

| Tier | Sticker | Per-week after cut |
|---|---|---|
| Weekly | $6.99 / wk | **$5.94 / wk** |
| Annual | $109.99 / yr | $93.49 / yr → **$1.80 / wk** |

---

## Net Margin Per User

| Tier | Heavy user (all caps maxed) | Average user |
|---|---|---|
| **Weekly** | $5.94 − $1.04 = **+$4.90 / wk · 82%** | $5.94 − $0.30 = **+$5.64 / wk · 95%** |
| **Annual** | $1.80 − $1.04 = **+$0.76 / wk · 42%** | $1.80 − $0.30 = **+$1.50 / wk · 83%** |

Every cell positive. No tier bleeds.

---

## Per-year Profit Per User

| Tier | Heavy | Average |
|---|---|---|
| Weekly | **$254.80 / yr** | **$293.28 / yr** |
| Annual | **$39.52 / yr** | **$78.00 / yr** |

Weekly subscribers are the cash cow — much higher per-year profit despite shorter retention. Annual subscribers are the durability play (committed LTV, low churn) at lower per-year dollars.

---

## The Voice Lever

Voice is **96% of the heavy-user cost** ($0.90 of $1.04 weekly). Every other cap combined is $0.13 / wk worst case. Implications:

- Voice cap above **~25 min/wk on annual** without raising the price → annual heavy users start bleeding.
- Renders, rizz, and scans can move up generously with negligible cost impact. We could give 5 renders / 30 screenshots / 3 scans per week and the cost barely moves.
- The Sunday → Monday rollover bleed (closed in v278) was costing ~$0.90 / wk per exploiter on doubled voice. Now structurally impossible because each user's 7-day window is anchored to their own first-usage timestamp.

---

## What This Model Does NOT Cover

- **Paid acquisition cost (CAC).** Subtract whatever blended CAC you pay for installs from every margin number above.
- **Refunds and chargebacks.** Industry standard ~3–5% of revenue lost.
- **30% store cut after the SBP / first-$1M expires.** Multiply every revenue cell by 0.70 / 0.85 ≈ 18% revenue drop. Heavy annual margin gets thin (~$0.45 / wk) but stays positive.
- **Voice cost variance.** The $0.05 / min blended assumes typical 40/60 user/AI mix; chatty personas or long monologue replies push it up. Worst observed ceiling is ~$0.08 / min for very AI-heavy convos — heavy weekly margin still positive at that ceiling.
- **Backend egress.** Railway charges for outbound bandwidth. Per-user-per-week is tiny but if global concurrent voice spikes, add a 5–10% buffer to backend cost.

---

## TL;DR

Healthy at current caps with mini-realtime. No tier bleeds, no exploit windows after v278. Voice is the single variable worth watching. Don't raise voice caps without raising prices or splitting tiers.
