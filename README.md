# Browser Chooser

A small macOS menu for opening a web link in the browser profile you meant to use. It offers local Chrome and Microsoft Edge profiles plus Safari, with number keys or a click to choose. Built with AI using Codex, with human feedback and local testing.

Inspired by [Browserosaurus](https://github.com/will-stone/browserosaurus). This is an independent Swift/AppKit implementation, not a fork or affiliate.

![Browser Chooser menu with demo profiles](docs/screenshots/chooser.png)

*The screenshots use demo profile names and `example.com`, not personal browser data.*

## What it does

- Handles `http` and `https` links. Custom app schemes stay with their own handlers.
- Reads Chrome and Edge profile names from local browser metadata when the chooser opens. It does not read cookies or account credentials.
- Opens the link in the chosen profile. Safari opens without a profile choice.
- Shows the destination host below the list. Choose with a click or keys `1` to `9`; press Escape or click away to cancel.
- Opens a manual URL entry window when launched without a link:

![Manual web link entry with a demo URL](docs/screenshots/url-entry.png)

## Build and try it

Requires macOS 13 or later, Swift 6, and a valid Apple Development or Developer ID Application signing identity on your Mac. There is no prebuilt or notarized download.

```sh
swift test
./scripts/build-app.sh
./scripts/trial-url.sh
```

The build script creates `build/Browser Chooser.app` and signs it with the only valid matching identity it finds. If you have more than one, set `BROWSER_CHOOSER_SIGN_IDENTITY` to the identity fingerprint before building. The trial script opens `https://example.com` by default, or accepts another web URL as its first argument. It does not register the app as a URL handler or change your default browser.

To install the signed build in `/Applications` and register its web link claims:

```sh
./scripts/install-app.sh
open -a '/Applications/Browser Chooser.app' 'https://example.com'
```

The install script does **not** change your default browser. On the Mac used for development, Browser Chooser did not appear in the System Settings default browser menu. After verifying the installed app, opt in to the supported macOS API for `http` and `https`:

```sh
swift scripts/set-default-browser.swift --apply
```

The helper reads back both web handlers and warns if macOS also changes your HTML file opener. If it does, restore your previous HTML app through Finder's **Get Info > Open with > Change All**. The helper does not change file or custom-scheme handlers itself.

macOS may ask for **Files & Folders** access to read Chrome and Edge profile names. If the chooser reports that it cannot read profiles, allow Browser Chooser access in **System Settings > Privacy & Security > Files & Folders**, then fully quit and reopen the app.

## Status

This is a source-built personal project shared for others to inspect and try. Local testing covered profile discovery, web URL validation, keyboard and pointer selection, launch into specific installed profiles, and default web link routing. No prebuilt signed release is included.

## License

MIT. See [LICENSE](LICENSE).
