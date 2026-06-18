# Daily Maintenance Bot — setup

The workflow `.github/workflows/daily-maintenance.yml` runs once a day. Each run:

1. Reads `ROADMAP.md` and picks the top open `- [ ]` item.
2. Opens a tracking **issue** (label `daily-bot`).
3. Creates a branch and implements a small, focused fix (with tests/docs).
4. Validates locally: `dart format`, `flutter analyze --no-fatal-infos`, `flutter test`.
5. Opens a **PR** that says `Closes #<issue>` and enables **auto-merge**.
6. The PR merges automatically **only after CI is green** (`flutter analyze & test`,
   plus the native Android/iOS builds).

You can also trigger it manually: **Actions → Daily Maintenance Bot → Run workflow**,
optionally passing a `task_hint`.

## One-time configuration (required)

### 1. Secrets — Settings → Secrets and variables → Actions

| Secret | Purpose |
| --- | --- |
| `ANTHROPIC_API_KEY` | Anthropic API key the agent runs on. |
| `AUTOMATION_TOKEN` | A fine-grained **PAT** (or GitHub App token) with `contents: write`, `issues: write`, `pull requests: write`. **Required** — see the note below. |

> **Why a PAT and not the default `GITHUB_TOKEN`?** GitHub deliberately does **not**
> re-trigger workflows for pushes/PRs created with the built-in `GITHUB_TOKEN`. If the
> bot used it, the CI workflow would never start on the bot's PR, so the required
> check would never go green and auto-merge would wait forever. Pushing/opening the PR
> with a PAT makes CI fire normally. If you omit `AUTOMATION_TOKEN`, the workflow falls
> back to `GITHUB_TOKEN` and still opens the issue/PR, but you'll have to merge by hand.

The native CI builds also need the Mapbox secrets already used by `ci.yml`:
`MAPBOX_DOWNLOADS_TOKEN` (and `MAPBOX_ACCESS_TOKEN` for the release APK).

### 2. Enable auto-merge — Settings → General → Pull Requests

Tick **"Allow auto-merge"**. Without this, `gh pr merge --auto` cannot arm.

### 3. Protect `main` — Settings → Branches → Add branch ruleset / protection

Protect `main` and mark the CI job **"Dart analyze & test"** (and, if you want the
native builds to gate too, the Android/iOS jobs) as **required status checks**. This is
what makes "auto-merge after CI passes" actually safe: a red build blocks the merge.

## Tuning

- **Schedule:** edit the `cron` in the workflow (`0 6 * * *` = 06:00 UTC daily).
- **Scope/queue:** edit `ROADMAP.md`. The bot always works the topmost open item, so
  reorder items to reprioritize.
- **Turn off auto-merge** (review every PR yourself): remove step 10 from the prompt
  (`gh pr merge --squash --auto`) — the bot will then only open PRs.
- **Stop it entirely:** disable the workflow in the Actions tab, or delete the file.
