#!/bin/zsh
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_app="$root_dir/build/Browser Chooser.app"
installed_app="/Applications/Browser Chooser.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$source_app" ]]; then
  print -u2 "Build the app first: ./scripts/build-app.sh"
  exit 1
fi
pgrep_status=0
/usr/bin/pgrep -x BrowserChooser >/dev/null || pgrep_status=$?
if (( pgrep_status == 0 )); then
  print -u2 "Quit Browser Chooser before installing a new build."
  exit 1
elif (( pgrep_status != 1 )); then
  print -u2 "Could not check whether Browser Chooser is running."
  exit 1
fi
/usr/bin/codesign --verify --strict "$source_app"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")"
if [[ "$bundle_id" != "dk.lvc.browserchooser" ]]; then
  print -u2 "Unexpected bundle identifier: $bundle_id"
  exit 1
fi
if [[ -e "$installed_app" ]]; then
  installed_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist")"
  if [[ "$installed_bundle_id" != "$bundle_id" ]]; then
    print -u2 "Refusing to replace an unrelated app at $installed_app"
    exit 1
  fi
fi

staging_dir="$(/usr/bin/mktemp -d '/Applications/.browser-chooser-install.XXXXXX')"
trap 'if [[ -d "$staging_dir" ]]; then /usr/bin/trash "$staging_dir"; fi' EXIT
staged_app="$staging_dir/Browser Chooser.app"
/usr/bin/ditto "$source_app" "$staged_app"
/usr/bin/codesign --verify --strict "$staged_app"
if [[ -e "$installed_app" ]]; then
  /usr/bin/trash "$installed_app"
fi
/bin/mv "$staged_app" "$installed_app"
/usr/bin/codesign --verify --strict "$installed_app"
"$lsregister" -f "$installed_app"
print "Installed and registered: $installed_app"
print "Default browser settings were not changed."
