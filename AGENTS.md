# Agent guide

Lead with the outcome. Keep changes small, native to macOS, and dependency-free unless a task explicitly justifies a dependency.

## Product boundaries

- This app displays only `spend_control.individual_limit` from `GET /backend-api/wham/usage`.
- Treat the endpoint as undocumented. Do not infer data from rate-limit, plan, credit, or unrelated response fields.
- Read OAuth credentials only from `~/.codex/auth.json` (or `CODEX_AUTH_FILE`) at request time. Never log, commit, cache, or display tokens, account IDs, emails, or raw responses.
- Keep the menu-bar application an accessory app: no Dock icon and no main application window unless a task requires one.

## Engineering rules

- Use `rtk` to prefix shell commands. Use `apply_patch` for file edits.
- Preserve existing user changes and do not use destructive Git commands.
- Prefer small Swift types with injectable dependencies; keep networking, persistence, metrics, notification policy, and AppKit UI separate.
- Add or update focused tests for parsing, persistence, metric math, and notification policy before considering a feature complete.
- Before handoff, run `rtk swift test`, `rtk swift build`, `rtk scripts/build-app.sh`, and `rtk git diff --check` when relevant.

## Working tracker

`PROJECT_TRACKER.md` is the source of truth for planned work. Update task status, acceptance evidence, and dependencies whenever work changes scope or completes. Do not mark a task done without its stated verification.
