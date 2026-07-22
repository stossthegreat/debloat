# Debloat OS

**The face under the bloat.** Scan your face, run the daily debloat
system, see the AI-rendered drained version of you, and track the
60-day ascension.

- `lib/` — Flutter app (SCAN / DEBLOAT / MIRROR / ASCEND)
- `backend/` — API (scan analysis, honest rating, Mirror renders)
- Bundle id: `com.debloatos.app`

## Build

```bash
flutter pub get
flutter run
```

Release signing: generate a fresh upload keystore (see
`android/app/build.gradle.kts`) — never reuse another app's key.
