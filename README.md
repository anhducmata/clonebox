# CloneBox

Drop a macOS app into the box and get a second copy with its own login.
Example: `Claude` (personal account) and `Claude Work` (company account) side by side, each with
its own Dock icon.

Works for Electron and Chromium apps (Claude, Slack, Notion, Postman, Chrome…). Native and
App Store apps (Office, Teams…) are refused: macOS ties their data to the app identity.

## Build and install

No Xcode needed, only the Command Line Tools.

```bash
./scripts/build-app.sh --install     # builds build/CloneBox.app and copies it to ~/Applications
```

## Use

1. Open CloneBox and drop an app on the box (or click the box to pick one).
2. Type a profile name, pick a badge colour, press **Create clone**.
3. The clone appears in `~/Applications` as `<App> <Profile>.app`. Open it and sign in.

**First sign-in:** the browser sends the login back through a link such as `claude://`. Close
the other windows of that app first, or choose **Send sign-in links here** in the clone's menu,
sign in, then **Send sign-in links to original**.

Command line (same binary): `CloneBox inspect|create|list|rebuild|delete`.

## How it works

| Step | What | Why |
|---|---|---|
| Copy | `cp -Rc` (APFS copy-on-write) | A full copy that uses almost no extra disk |
| Identity | new `CFBundleIdentifier`, display name, badged icon | macOS and the Dock treat it as a different app |
| Launcher | `clonebox-launcher` becomes the main executable | Starts the real binary with `--user-data-dir=<own folder>` |
| Sign | ad-hoc `codesign`, inside-out | macOS will not start a changed bundle otherwise |

- Data (the login) lives in `~/Library/Application Support/CloneBox/<slug>/data`.
- `Contents/Resources/clonebox.json` inside each clone holds its settings.
- On each start the launcher compares versions with the original app and rebuilds the clone
  when the original was updated. The login stays.
- Deleting moves the clone to the Trash; the login data only when you choose so.

## Limits

- `CFBundleName` must stay unchanged (Electron finds its helper apps by it), so the menu bar
  still says the original name. Dock and Finder show the clone's name.
- Clones start with `--use-mock-keychain`: the saved session is encrypted with a fixed key
  instead of a Keychain key. Passkeys and Microsoft work sign-in may not work in a clone.
- The app's own updater cannot update a clone; the launcher rebuild replaces it.
- macOS asks again for microphone, camera and notification permission per clone, and may ask
  again after a rebuild.
- Tested with Claude 6.28899.6 on macOS 27.2. Other apps: not yet tested.
