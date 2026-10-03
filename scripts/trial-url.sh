#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_executable="$root_dir/build/Browser Chooser.app/Contents/MacOS/BrowserChooser"

if [[ ! -x "$app_executable" ]]; then
  print -u2 "Build the app first: ./scripts/build-app.sh"
  exit 1
fi

# Direct execution does not register URL handlers or change the default browser.
exec "$app_executable" "${1:-https://example.com}"
