# <div align=center><img width="200" alt="cclogo" src="https://github.com/user-attachments/assets/a5acbd6f-9258-4bc2-be6f-c322a580a006" /><br/>CreditCrunch</div>

<p align=center>A macOS menu-bar app to help you keep track of your credit usage.</p>

## Quick start

1. From the repository root, build CreditCrunch and link it into your Applications folder:

```sh
./scripts/build-and-link-app.sh
```

2. Launch it from the command line:

```sh
open "$HOME/Applications/CreditCrunch.app"
```

The app has no Dock icon. Its Applications/Finder icon uses the bundled CreditCrunch artwork, while its menu-bar icon uses a 16-dot usage progress ring. Dots fill clockwise from 12:00 (25% reaches 3:00; 50% reaches 6:00); the color starts green at 0% usage, moves through yellow, and reaches red near 100% usage. Its menu shows spend limit, spent, remaining, remaining percentage, reset value when provided, last update, Refresh Now, Preferences, and Quit.

## Configuration

At each refresh the app reads `~/.codex/auth.json`, or `CODEX_AUTH_FILE` when set. It accepts either snake_case or camelCase access-token/account-ID keys under `tokens`. The account header is sent only when an account ID exists.

## Screenshots
<img width="400" alt="CreditCrunch app over target" src="https://github.com/user-attachments/assets/b9a3f796-b6f7-42b4-9211-d1237485d867" />
<img width="424"  alt="CreditCrunch app under target" src="https://github.com/user-attachments/assets/9e09aaa2-a3df-4589-91e7-7defe84c6301" />

