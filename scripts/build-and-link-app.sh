#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/dist/CreditCrunch.app"
applications_directory="$HOME/Applications"
link="$applications_directory/CreditCrunch.app"

"$root/scripts/build-app.sh"
mkdir -p "$applications_directory"

if [[ -e "$link" && ! -L "$link" ]]; then
  echo "Refusing to replace non-symlink application: $link" >&2
  exit 1
fi

ln -sfn "$app" "$link"
echo "Linked $link -> $app"
