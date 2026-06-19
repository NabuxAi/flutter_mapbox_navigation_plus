# Roadmap & Gap Analysis

This file is **two things at once**:

1. A human-readable analysis of what is still missing or rough in
   `flutter_mapbox_navigation_plus` for it to be considered "complete".
2. The **work queue for the daily maintenance bot**
   (`.github/workflows/daily-maintenance.yml`). Each run picks the first
   unchecked `- [ ]` item from the highest-priority section, ships it as a small
   PR, and ticks the box.

Conventions:

- `- [ ]` = open, `- [x]` = done (the bot checks the box in the same PR).
- Keep every item **small and independently shippable** (one PR each).
- Higher sections have higher priority. The bot works top to bottom.

---

## P1 — Correctness, packaging & consistency

- [ ] **Fix the pub.dev/packaging inconsistency.** `pubspec.yaml` sets
  `publish_to: none`, yet the README shows a pub.dev version badge and install
  instructions that point at `pub.dev/packages/flutter_mapbox_navigation_plus`.
  Decide on one story (publish to pub.dev *or* document git/GitHub-Packages
  install) and make the README, badges and pubspec agree.
- [ ] **Graceful behaviour on unsupported platforms.** The platform interface
  throws `UnimplementedError` for desktop, and web is a stub that only returns
  `getPlatformVersion`. Calls on Linux/macOS/Windows/web should fail with a
  clear, actionable `UnsupportedError` message instead of a generic
  "has not been implemented", and the README should state the supported matrix.
- [ ] **Migrate the web stub off `dart:html`.** `lib/src/flutter_mapbox_navigation_web.dart`
  imports the deprecated `dart:html`. Move to `package:web` + `dart:js_interop`
  so the package keeps building on modern Flutter web toolchains.
- [ ] **Surface navigation/build errors to Dart.** Audit the native event
  bridge and make sure route-build failures and runtime navigation errors are
  emitted as a typed error event (not silently swallowed), with parity across
  Android and iOS.

## P2 — Test coverage

- [ ] **Unit-test model (de)serialization.** Add `fromJson`/`toJson` round-trip
  tests for `MapBoxOptions`, `MapMarker`, `OfflineRegion`, `RouteAlternative`,
  `RouteProgressEvent`, `RouteLeg`, `RouteStep` and the event types under
  `lib/src/models/`. Current `test/` is ~184 lines and barely touches these.
- [ ] **Test the embedded `MapBoxNavigationViewController` method-channel
  contract** (markers add/remove/clear, `selectAlternativeRoute`, `addWayPoints`,
  offline calls) against a mocked method channel.
- [ ] **Add a `dart format --set-exit-if-changed` check to CI** so formatting
  stays consistent.
- [ ] **Add test coverage reporting** (`flutter test --coverage`) and upload the
  lcov report as a CI artifact.

## P3 — Lint debt & code health

- [ ] **Burn down the `very_good_analysis` info-level lints** so CI no longer
  needs `--no-fatal-infos`. Do it in small, file-scoped passes (a few files per
  PR) and only flip CI to fatal-infos once the tree is clean.
- [ ] **Modernise the SDK constraint.** `environment.sdk` is `>=2.19.4`; evaluate
  bumping to a Dart 3 lower bound and adopting Dart 3 idioms where it improves
  null-safety/sealed handling without breaking consumers.

## P4 — Docs & repository hygiene

- [ ] **Add `CONTRIBUTING.md`** describing how to set up Mapbox tokens, run the
  example, run `flutter analyze`/`flutter test`, and the branch/PR conventions.
- [ ] **Add GitHub issue & PR templates** under `.github/` (bug report, feature
  request, PR checklist).
- [ ] **Add `dartdoc` generation** (a CI job that builds API docs and, optionally,
  publishes them) and document every public API member.
- [ ] **Add Dependabot** (`.github/dependabot.yml`) for GitHub Actions and the
  Android Gradle dependencies.
- [ ] **Document the supported feature matrix** (full-screen vs embedded vs
  free-drive; markers/avoid/alternatives/stops/offline/CarPlay/Android Auto)
  in a single table in the README, with the per-platform "known limitations"
  consolidated (today they are scattered across `docs/IOS_MANUAL_TEST.md` and
  `docs/CARPLAY_ANDROID_AUTO.md`).

## P5 — Feature parity & polish

- [ ] **Embedded view close/end-navigation affordance on iOS.** `docs/IOS_MANUAL_TEST.md`
  notes there is no built-in close button on the embedded view; add an optional
  one (or document the host-app pattern) at parity with Android.
- [ ] **Verify offline-region progress-event parity** between Android and iOS and
  add an example screen that downloads a region and shows progress.
- [ ] **Add an integration/golden test for the event stream** that feeds sample
  native payloads through the Dart parsing layer.

---

> When every box above is checked, the bot will analyze the repository and append
> new, concrete items here before picking one — so this queue is self-refilling.
