# Browser Chooser

Browser Chooser is a personal macOS successor inspired by [Browserosaurus](https://github.com/will-stone/browserosaurus). It is an independent Swift/AppKit implementation, not a fork of or affiliated with Browserosaurus.

It chooses a browser for `http` and `https` links. It reads local Chrome and Microsoft Edge profile metadata when the chooser opens, then offers those profiles and Safari. Custom app schemes such as `zoommtg:` are outside its scope.

## Build and test

```sh
timeout 300 swift test
timeout 300 ./scripts/build-app.sh
```

The app bundle is `build/Browser Chooser.app`. Build output is ignored by Git. The build script signs with the single valid Apple Development or Developer ID Application identity on the Mac. If several are installed, set `BROWSER_CHOOSER_SIGN_IDENTITY` to the intended identity's fingerprint. It fails when no suitable identity is available.

## Local URL trial

```sh
timeout 300 ./scripts/trial-url.sh
```

This runs the app bundle directly with `https://example.com`. No URL handler is registered and the macOS default browser is not changed. Pass another `http` or `https` URL as the first argument to try it. You can also open the app bundle directly, enter a web URL, and click **Open chooser**. Other schemes are rejected. The chooser shows the destination host and offers available Chrome and Edge profiles plus Safari. Click an option, press `1` through `9`, or press Escape to cancel. Selecting an option opens the URL in that browser.

The app queues incoming links, so each link gets its own chooser. A failed browser launch leaves the chooser open for another selection. Chromium launches use the exact profile directory with `/usr/bin/open`; Safari is targeted by its bundle identifier.

Chrome and Edge profile data lives in folders protected by macOS. If the chooser says it cannot read profiles, open **System Settings > Privacy & Security > Files & Folders** and allow **Browser Chooser** access to both browser folders. If the switches do not stick, remove only the Browser Chooser entry there, open a link with the app to trigger a fresh access request, then allow both folders. Fully quit Browser Chooser and launch it again after changing access; an already running process can keep the earlier denial. Earlier ad-hoc builds used a changing code hash, so a grant made to one of those builds may need renewal for the signed app. The build script now uses a stable certificate identity so subsequent builds retain the same designated requirement.

The local trial verified that the chooser lists Chrome and Edge profiles plus Safari, opens the exact requested URL in the selected Chrome work and consulting profiles and Edge profile, rejects custom schemes, and cancels with Escape. These checks used the signed bundle without registering it as the default browser.

## Default browser setup

The bundle declares `http` and `https` support, but this repository does not register it as a handler or change the system default. Setting it as the default web browser is a separate, explicit manual choice in macOS settings.
