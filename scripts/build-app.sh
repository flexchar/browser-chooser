#!/bin/zsh
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"
if [[ -n "${BROWSER_CHOOSER_SIGN_IDENTITY:-}" ]]; then
  sign_identity="$BROWSER_CHOOSER_SIGN_IDENTITY"
else
  identities=("${(@f)$(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[0-9]+\) ([A-F0-9]{40}) "(Apple Development|Developer ID Application):[^"]+".*/\1/p')}")
  if (( ${#identities[@]} != 1 )); then
    print -u2 "Expected one valid Apple Development or Developer ID Application signing identity; set BROWSER_CHOOSER_SIGN_IDENTITY explicitly."
    exit 1
  fi
  sign_identity="$identities[1]"
fi
swift build -c release
app_dir="$root_dir/build/Browser Chooser.app"
if [[ -e "$app_dir" ]]; then
  /usr/bin/trash "$app_dir"
fi
mkdir -p "$app_dir/Contents/MacOS"
cp App/Info.plist "$app_dir/Contents/Info.plist"
cp .build/release/BrowserChooser "$app_dir/Contents/MacOS/BrowserChooser"
codesign --force --deep --sign "$sign_identity" "$app_dir"
echo "Built: $app_dir"
