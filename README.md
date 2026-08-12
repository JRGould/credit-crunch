# CreditCrunch

A dependency-free macOS menu-bar app for the `spend_control` portion of Codex/ChatGPT usage. It deliberately displays no rate-limit, plan, credit-balance, or other response fields.

## Build and run

```sh
swift test
swift run CodexCreditsMenubar
```

Build a double-clickable app bundle:

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
open dist/CreditCrunch.app
```

To rebuild and link the app into your Applications folder:

```sh
chmod +x scripts/build-and-link-app.sh
scripts/build-and-link-app.sh
open ~/Applications/CreditCrunch.app
```

The app has no Dock icon. Its Applications/Finder icon uses the bundled CreditCrunch artwork, while its menu-bar icon uses a 16-dot usage progress ring. Dots fill clockwise from 12:00 (25% reaches 3:00; 50% reaches 6:00); the color starts green at 0% usage, moves through yellow, and reaches red near 100% usage. Its menu shows spend limit, spent, remaining, remaining percentage, reset value when provided, last update, Refresh Now, Preferences, and Quit.

The `Debug` submenu includes a local-only usage simulation. It advances from 0% to 100% in 30 seconds, holds the completed display for five seconds, then restores and refreshes the actual account usage.

## Configuration

At each refresh the app reads `~/.codex/auth.json`, or `CODEX_AUTH_FILE` when set. It accepts either snake_case or camelCase access-token/account-ID keys under `tokens`. The account header is sent only when an account ID exists.

The default request target is `https://chatgpt.com/backend-api/wham/usage`. Set `CODEX_CHATGPT_BASE_URL` to change the base, for example a local test server base ending in `/backend-api`. The refresh interval defaults to 15 minutes and can be changed to 5, 15, 30, or 60 minutes in Preferences; it is persisted in macOS UserDefaults.

## Design and privacy

Authentication is loaded only immediately before the request. Tokens, account IDs, and response payloads are never logged, cached, or persisted. The parser reads only `spend_control`; it calculates missing remaining figures from values inside that object. Settings contains reserved persisted flags for future notification/cache work, but neither notifications nor caching is implemented.

The endpoint and schema are undocumented and may change. A failed request leaves any prior display intact and shows a generic, non-sensitive menu error.
