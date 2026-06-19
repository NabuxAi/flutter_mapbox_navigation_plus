# Project guide for AI agents

`flutter_mapbox_navigation_plus` is a Flutter **plugin** that adds Mapbox
turn-by-turn navigation (Navigation SDK v3) to Flutter apps, with native Android
(Kotlin) and iOS (Swift) implementations plus an embeddable navigation view.

## Layout

- `lib/` — public Dart API. `lib/flutter_mapbox_navigation_plus.dart` is the
  barrel export. Implementation lives under `lib/src/` (method channel,
  platform interface, `embedded/`, and `models/`).
- `android/` — Kotlin plugin. The v3 sources live under `android/src/v3/...`.
- `ios/flutter_mapbox_navigation_plus/` — Swift Package (v3 SDK is SPM-only).
- `example/` — runnable demo app, including a custom-UI screen
  (`example/lib/custom_nav_ui.dart`).
- `test/` — Dart unit tests.
- `docs/` — integration guides (CarPlay/Android Auto, iOS manual test).
- `ROADMAP.md` — gap analysis **and** the daily bot's work queue.

## How to validate a Dart change (no Mapbox token needed)

```bash
flutter pub get
dart format .
flutter analyze --no-fatal-infos
flutter test
```

`flutter analyze` runs with `--no-fatal-infos` because the tree still carries
pre-existing `very_good_analysis` info-level lints (tracked in ROADMAP P3). Do
not introduce **new** warnings or errors.

Native Android/iOS builds require `MAPBOX_DOWNLOADS_TOKEN` (and, for rendering,
a public `pk` token); those run in CI (`.github/workflows/ci.yml`) on the PR, not
locally in the daily bot.

## Conventions

- Lints: `package:very_good_analysis` (see `analysis_options.yaml`).
- Commits: Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).
- Keep public Dart APIs documented; keep Android/iOS behaviour at **parity** —
  if you add a capability on one platform, note the other in the PR.
- Update `CHANGELOG.md` for any user-facing change and bump `version` in
  `pubspec.yaml` only for a release (not for every small PR).
- Keep changes **small and focused** — one concern per PR.

## What not to touch without an explicit task

- The pinned Mapbox SDK versions (Android Gradle / iOS `Package.swift`).
- Secrets, tokens, or the `.netrc`/Gradle credential handling in CI.
- The release pipeline (`.github/workflows/release.yml`).
