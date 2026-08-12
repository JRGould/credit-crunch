# Project tracker

Status: `planned` means designed but not started; `ready` means unblocked; `done` requires the listed acceptance checks. This tracker covers the next phase after the live menu-bar usage display.

## Completed

| ID | Status | Task | Evidence |
| --- | --- | --- | --- |
| D1 | done | Add a local-only Debug usage-ring simulation that advances 0% to 100% over 30 seconds and restores actual usage after five seconds. | Pure progress math is covered by unit tests; no account data is changed or persisted. |

## Now

| ID | Status | Task | Depends on | Acceptance checks |
| --- | --- | --- | --- | --- |
| P1 | done | Define and implement a versioned local `UsageSnapshot` model plus a `UsageHistoryStore` protocol. Store only the parsed spend-control values, collection time, and schema version. | — | Codable round-trip and schema-migration tests; no raw payload, OAuth token, account ID, email, or other PII in the persisted record. |
| P2 | done | Add an atomic history store under Application Support. Write one snapshot after each successful refresh; use restrictive file permissions, bounded retention, and a corruption-safe recovery path. | P1 | Tests cover atomic write, read, corrupt-file recovery, retention pruning, and file permissions. |
| P3 | done | Define metric semantics and build a pure metrics engine: current-day usage, daily burn rate, and projected spend-control exhaustion date. | P1, P2 | Tests cover timezone/day boundaries, sparse history, reset boundaries, zero/negative burn rate, and an explicitly unavailable projection. |
| P9 | done | Fix Preferences window lifecycle: when its window exists but is behind another app, selecting `Preferences…` must activate and bring that same window to the front rather than create another. | — | AppDelegate reuses the existing window and activates it before bringing it frontmost; closing the Preferences window does not terminate the accessory app. |
| P10 | done | Move the local usage simulation controls from the Debug menu into a Debug section of Preferences. Let users edit and persist the simulation duration and post-simulation restore delay with safe validation. | D1, P9 | Preferences contains labelled duration/delay fields; configuration tests cover validation and persistence, and the simulation uses the saved timings before restoring actual usage. |

## Next

| ID | Status | Task | Depends on | Acceptance checks |
| --- | --- | --- | --- | --- |
| P4 | done | Surface derived metrics in the menu and a compact history/details view, with clear “insufficient history” states. | P3 | Presentation tests cover formatting, sparse-history states, confidence, and the compact pace dashboard. |
| P5 | done | Add configurable local notifications for actionable transitions (for example, remaining-percent thresholds, approaching reset, or projected exhaustion). | P3 | Notification tests cover threshold crossings, unavailable data, deduplication, and injected notifier/clock behavior. |
| P6 | done | Add preferences for history retention and notification thresholds; provide a “clear local history” action with confirmation. | P2, P5 | AppSettings and AppDelegate persist/validate settings and expose a confirmation-gated clear-cache action. |
| P11 | done | Make weekday pacing allocation reset-time-aware: count the reset day’s 9:00–17:00 pre-reset fraction while keeping the target a daily allocation rather than converting it to an hourly target. | P3, P4 | Focused tests cover a 5pm full reset workday, a 1pm fractional reset workday, and the dashboard’s 7.3k/2-slot daily target calculation. |
| P12 | done | Keep the active day’s pacing target fixed across refreshes rather than comparing cumulative daily use with the shrinking live balance. | P1, P4, P11 | `UsagePresentationTests` covers a reset-day target held at 7.3k while usage rises and verifies its 7.25k under-target headroom equals the live balance; sparse reset-day history remains explicitly unavailable. `swift test` (37), `swift build`, `scripts/build-app.sh`, and `git diff --check` passed on 2026-07-31. |
| P13 | done | Add a compact billing-period summary below the daily pacing view. | P1, P4 | The menu now shows `Used X of Y` and a full-width, non-wrapping localized reset time beneath the seven-day pacing chart, using only the latest minimized snapshot; unavailable values remain explicit. `swift test` (39), `swift build`, `scripts/build-app.sh`, and `git diff --check` passed on 2026-07-31. |
| P14 | done | Retain prior billing-period daily usage in the seven-day pacing chart after a reset. | P1, P4 | Regression coverage keeps valid prior-period bars, canonicalizes equivalent reset timestamps that vary by seconds, preserves active-period target/current-day usage, and leaves reset-day or following-day cross-period ambiguity blank rather than inventing a value. `swift test` (45), `swift build`, `scripts/build-app.sh`, and `git diff --check` passed on 2026-07-31. |
| P15 | done | Add a billing-period daily-usage chart with a muted, weekday-aligned prior-period comparison. | P1, P4, P14 | The compact period strip shows current-period daily bars only for elapsed dates, a visibly muted prior-period comparison aligned by weekday occurrence, reset-boundary gaps, and safe partial-day usage after a reset. It retains a concise reset label without enlarging the menu. `swift test` (46), `swift build`, `scripts/build-app.sh`, and `git diff --check` passed on 2026-07-31. |
| P16 | done | Preserve daily history across high-frequency refreshes so cross-period charts remain useful. | P1, P14, P15 | When raw history reaches its sample limit, the store retains each calendar day's opening and closing sample for every observed reset identity, preserving safe daily deltas and reset-boundary detection instead of discarding the prior period. Storage regression coverage verifies compaction. `swift test` (47), `swift build`, `scripts/build-app.sh`, and `git diff --check` passed on 2026-08-05. |
| P17 | done | Backfill missing historical chart days from the account’s daily workspace-usage analytics endpoint. | P1, P14, P15, P16 | On a fresh installation, a one-time launch import fetches the prior calendar month through today using the existing auth file at request time. It records successful completion locally, stores only daily date/credit totals in a separate 0600 local file, and fills historical chart gaps without affecting live balance, pacing, or targets. Parser, storage, and chart-fallback coverage passed with `swift test` (50), `swift build`, `scripts/build-app.sh`, and `git diff --check` on 2026-08-05. |
| P18 | done | Rename the user-facing menu-bar app to CreditCrunch. | — | The application bundle, executable, macOS display name, menu text, preferences, cache-clear copy, and build/run documentation use CreditCrunch. Stable internal identifiers remain unchanged to preserve existing local data. |
| P19 | done | Add a build-and-link script for the local Applications folder. | P18 | `scripts/build-and-link-app.sh` rebuilds CreditCrunch and creates `~/Applications/CreditCrunch.app` as a symlink, refusing to replace a non-symlink app bundle. |
| P20 | done | Add the supplied CreditCrunch artwork as the macOS app icon. | P18 | The build copies `CreditCrunch.icns` into the app bundle and declares it with `CFBundleIconFile`; the linked Applications bundle contains the icon. |

## Hardening

| ID | Status | Task | Depends on | Acceptance checks |
| --- | --- | --- | --- | --- |
| P7 | done | Make endpoint changes diagnosable without exposing sensitive data: typed errors, last-success metadata, and parser-contract fixtures. | P1 | Parser tests cover missing/null `spend_control`, numeric strings, number values, and nested `individual_limit`; error paths expose generic messages rather than response bodies. |
| P8 | done | Add an end-to-end local smoke path using a fixture HTTP server and an isolated auth file. | P2, P4, P5 | Fixture smoke test exercises an isolated auth file and local fixture endpoint; refresh integration writes minimized snapshots and evaluates presentation/notification paths without the live endpoint. |

## Decisions already made

- The primary displayed data is `spend_control.individual_limit`, not the unpopulated rate-limit fields.
- Default refresh remains 15 minutes.
- History must contain only minimized, parsed usage snapshots; authentication stays in Codex’s existing auth file.
- Projections are estimates, not guarantees, and must be absent when history is insufficient or a reset makes the calculation ambiguous.
