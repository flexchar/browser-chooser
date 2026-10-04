# Browser Chooser

Lane: 💼

- Personal, independent Swift/AppKit successor inspired by Browserosaurus. Do not copy upstream code or claim this repository is a fork or affiliate.
- Scope: `http` and `https` links only. Leave custom app schemes to their existing handlers.
- Never change the macOS default browser or register URL handlers without Lukas's explicit request. The local trial runs the app bundle executable directly.
- Build and verify with `timeout 300 swift test` and `timeout 300 ./scripts/build-app.sh`. Build output under `.build/` and `build/` stays untracked. Run `timeout 300 ./scripts/trial-url.sh` for an approved manual URL trial.
- Build signing uses an existing, unique valid Apple Development or Developer ID Application identity, or `BROWSER_CHOOSER_SIGN_IDENTITY` when explicitly set. Never add certificate or key material to the repo. Ad-hoc signatures caused macOS Files & Folders grants to fail after rebuilds.
- After renewing Files & Folders access, fully quit Browser Chooser before testing the signed bundle again. If switches revert, remove only its Files & Folders entry, trigger a fresh folder read, allow Chrome and Edge, then fully quit and relaunch. A running process can retain a denial even after macOS shows the switches on. Do not rebuild just to renew access.
- GUI testing requires a separate Computer Use approval. Shell builds and unit tests do not prove that a window renders or that browser selection works on screen.
- Profile display names are required in the chooser UI and may appear during an approved GUI test. Do not log profile account details, email addresses, or IDs, and never read cookies or credentials. Fake profile metadata in tests is fine.
- Local chooser preference: show Edge `Default` as `Personal` first, Chrome `Default` (JOE & THE JUICE) second, then keep the discovered order. Match by profile directory, keep launch routing unchanged, and never display or store account email addresses.
- Keep the chooser compact and place it beside the mouse pointer on that display, within its visible area. Avoid centering it on the screen.
- Use a small floating menu with slim profile rows, browser icons, numbered shortcut badges and a destination footer. Keep the title bar and large heading out of the chooser.
- Never remove files with `rm`. Move deletions to macOS Trash with `/usr/bin/trash`.
