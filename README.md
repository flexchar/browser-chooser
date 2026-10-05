# Browser Chooser

I keep separate browser profiles for personal and work, and I got tired of opening a link in the wrong one. Browser Chooser puts a small menu beside the pointer so I can choose the right profile with a click or a number key. It's my independent Swift/AppKit successor inspired by [Browserosaurus](https://github.com/will-stone/browserosaurus), not a fork or an affiliated project.

I've been enjoying prompting my AI agent, Codex, on the side to build small, practical tools that help me as I go, without getting in the way. Part of me misses spending days learning a language, a framework and its tooling, then building something myself and knowing every line. Yet here we are :)

![Browser Chooser menu with demo profiles](docs/screenshots/chooser.png)

*The screenshots use demo profile names and `example.com`, not my browser data.*

## What it does

- Offers local Chrome and Microsoft Edge profiles plus Safari for `http` and `https` links. Custom app schemes stay with their own handlers.
- Shows the destination host below the list. Click a row, press `1` to `9`, or press Escape to cancel.
- Can send an exact host straight to a chosen profile with an optional routing rule. If that profile is unavailable, the chooser opens with a warning.
- Opens this manual URL window when launched without a link:

![Manual web link entry with a demo URL](docs/screenshots/url-entry.png)

Chrome and Edge profile names come from local browser metadata when the chooser opens. The app does not read cookies or account credentials.

## Routing rules

Open Settings from the chooser gear, the manual URL window, or `⌘,`. Paste a web URL or enter a host such as `work.example.com`, choose a discovered profile, and save. Rules match that exact host only, so `sub.work.example.com` needs its own rule. You can edit, disable, or delete rules in Settings.

Once you've built the app, there's a command line path too:

```sh
APP='build/Browser Chooser.app/Contents/MacOS/BrowserChooser'
"$APP" --add-rule work.example.com --profile chrome:Default
"$APP" --explain-route https://work.example.com/path
```

`--explain-route` is a dry run and doesn't open a browser. `"$APP" --settings` opens Settings.

## Where settings live

The installed app uses `UserDefaults.standard` for the `dk.lvc.browserchooser` application domain, normally stored at `~/Library/Preferences/dk.lvc.browserchooser.plist`. The `routingRules.v1` key holds JSON-encoded data: each rule saves a normalized `host`, a browser/profile directory `profileID`, and an `enabled` flag. For example, `work.example.com` can point to `chrome:Default`. Rules don't save email addresses, full URLs, paths, queries, cookies, or credentials. They stay local and aren't uploaded to GitHub.

An enabled rule matches that exact host for both HTTP and HTTPS links, regardless of path. Disabled rules and unmatched hosts open the chooser. If the browser or saved profile directory isn't available, the chooser opens with a warning. App updates keep the same preferences; when moving to another Mac, check the profile IDs because its browser directories may differ.

Settings is the safest place to edit rules. macOS caches preferences, so don't hand-edit the plist. Once you've saved a rule, quit Browser Chooser and back up the whole app preferences domain to a private file outside this repo:

```sh
defaults export dk.lvc.browserchooser "$HOME/browser-chooser-settings.plist"
```

To restore it, quit the app, then run:

```sh
defaults import dk.lvc.browserchooser "$HOME/browser-chooser-settings.plist"
```

The backup can reveal sites you route, so keep it private. Importing may replace current preferences; reopen the app and check the rules afterward.

## Build and try it

You'll need macOS 13 or later, Swift 6, and a valid Apple Development or Developer ID Application signing identity on your Mac. I haven't published a prebuilt or notarized download.

```sh
swift test
./scripts/build-app.sh
./scripts/trial-url.sh
```

The build script creates `build/Browser Chooser.app` and signs it with the only valid matching identity it finds. If you have more than one, set `BROWSER_CHOOSER_SIGN_IDENTITY` to the identity fingerprint. The trial opens `https://example.com` by default, or another web URL passed as its first argument. It doesn't change your default browser.

To install the signed build in `/Applications` and check link delivery:

```sh
./scripts/install-app.sh
open -a '/Applications/Browser Chooser.app' 'https://example.com'
```

The install script registers the app but doesn't make it your default browser. On my Mac, it didn't appear in the System Settings default browser menu. After checking that links reach the installed app, you can set it as the default for `http` and `https` with:

```sh
swift scripts/set-default-browser.swift --apply
```

The helper reads back both web handlers. macOS may also change your HTML file opener; if it does, restore your previous app through Finder's **Get Info > Open with > Change All**. The helper doesn't change file or custom-scheme handlers itself.

macOS may ask for **Files & Folders** access to read Chrome and Edge profile names. If the chooser can't read profiles, allow Browser Chooser in **System Settings > Privacy & Security > Files & Folders**, then fully quit and reopen it.

This is a source-built personal project. I've tested profile discovery, URL validation, chooser selection, launch into installed profiles, and default web link routing locally. There are still rough edges, so feel free to poke around.

MIT licensed. See [LICENSE](LICENSE).
