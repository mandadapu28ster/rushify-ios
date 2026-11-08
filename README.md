# Rushify for iOS

Native SwiftUI client for the Rushify portfolio server. It is the iOS counterpart of the Android app
(`Rushify-Android`) and follows the same design: cache-first screens, one account's data never shown to
another, the password never stored (only the token, in the Keychain).

Requires iOS 17+, Xcode 16+.

## Build and test

```bash
brew install xcodegen
xcodegen generate            # creates Rushify.xcodeproj from project.yml
open Rushify.xcodeproj
```

Unit tests (about 440, against a stubbed network) and end-to-end tests (53, the real app driven through every screen):

```bash
xcodebuild test -project Rushify.xcodeproj -scheme Rushify \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RushifyTests -quiet
xcodebuild test -project Rushify.xcodeproj -scheme Rushify \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RushifyUITests -quiet
```

To run everything quicker (build once, unit tests, then the end-to-end tests on 4 cloned simulators; about 10 minutes instead of 15+):

```bash
scripts/test-all.sh            # uses the booted simulator; optional: scripts/test-all.sh <udid> <workers>
```

The end-to-end tests run the app in UI-test mode (debug builds only): `RUSHIFY_UITEST=1` signs in against canned responses from
`Rushify/UITestFixtures` (named `<METHOD>_<path>.json`), `signedout` starts from a fresh install and `expired` makes every
authenticated call answer 401. They never touch a real server, and the fixtures are left out of release builds.

Debug builds can sign in without typing a password, for testing against a real account in the simulator:

```bash
SIMCTL_CHILD_RUSHIFY_DEBUG_SERVER="http://host:8040" SIMCTL_CHILD_RUSHIFY_DEBUG_TOKEN="<jwt>" \
  xcrun simctl launch booted com.rushify.mobile
```

This code is not compiled into release builds.

## Releases (builds for testers)

Publishing a GitHub release (tag such as `v0.2.0`) runs the `Release iOS build` workflow. It runs the tests,
then attaches to the release (the slower end-to-end tests have their own manually triggered `UI tests` workflow):

- `Rushify-<version>.ipa`: unsigned device build, for sideloading (below)
- `Rushify-simulator-<version>.zip`: simulator build (needs a Mac with Xcode)
- `SHA256SUMS.txt`

No Apple Developer account or secrets are needed for this. A manual trial run (Actions, Release iOS build,
Run workflow) builds both and keeps them as a workflow artifact without publishing anything.

Create a release from the terminal:

```bash
gh release create v0.2.0 --generate-notes
```

### Installing on an iPhone without a developer account

Apple only lets an iPhone run apps that are signed. The `.ipa` on the release page is unsigned, so a free tool signs it with
**your own Apple Account** while you install it. No paid developer account is needed, and no prior sideloading knowledge either.
Follow the steps in order.

#### What you need

- An iPhone running **iOS 17 or later** (what Rushify needs), with a **passcode** set ([how](https://support.apple.com/en-us/119586)).
- A computer (Windows 10/11 64-bit, macOS, or Linux) and a **USB cable**. The computer is only needed for the install.
- An **Apple Account** (Apple ID). A spare one is a good idea.
- A **Wi-Fi** connection, not mobile data.
- **LocalDevVPN** on the iPhone, a free app that SideStore-style tools use to refresh your apps
  ([App Store](https://apps.apple.com/app/localdevvpn/id6755608044)). Open it and tap Connect. Allow the VPN configuration if it asks.
- **Windows only:** iTunes ([Microsoft Store](https://apps.microsoft.com/store/detail/9PB2MZ1ZMB1S) or
  [Apple](https://www.apple.com/itunes/download/win64)), so the computer can talk to the iPhone.
  **Linux only:** `usbmuxd` (`sudo apt install usbmuxd`).

Background reading: [SideStore prerequisites](https://docs.sidestore.io/docs/installation/prerequisites).

#### Step 1: Download the app

1. Open the [Releases page](https://github.com/mandadapu28ster/rushify-ios/releases) and pick the newest release.
2. Under **Assets**, download `Rushify-<version>.ipa` (not the `.zip`, which is for Mac simulators).
3. Keep the file somewhere easy to find, such as Downloads.

#### Step 2: Install iloader on the computer

[iloader](https://iloader.app/) is a free, open-source installer that signs and installs an `.ipa` for you.
Download it only from [iloader.app](https://iloader.app/) or its [GitHub releases](https://github.com/nab138/iloader/releases/latest):

- macOS: [`.dmg`](https://github.com/nab138/iloader/releases/latest/download/iloader-darwin-universal.dmg), or `brew install --cask iloader`
- Windows: [`.msi`](https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.msi) or [`.exe`](https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.exe)
- Linux: [`.deb`](https://github.com/nab138/iloader/releases/latest/download/iloader-linux-amd64.deb),
  [`.rpm`](https://github.com/nab138/iloader/releases/latest/download/iloader-linux-x86_64.rpm) or
  [AppImage](https://github.com/nab138/iloader/releases/latest/download/iloader-linux-amd64.AppImage)

#### Step 3: Install Rushify with iloader

1. Plug the iPhone into the computer with the cable. Unlock it and tap **Trust This Computer** if asked.
2. Make sure LocalDevVPN is connected on the iPhone.
3. Open iloader. Pick your iPhone from the device list.
4. Sign in with your Apple Account. If Apple sends a 6-digit code to your devices, type it in.
5. Choose the option to install an **IPA** and select the `Rushify-<version>.ipa` you downloaded.
6. Wait until iloader says it finished. Rushify now appears on the Home Screen.

#### Step 4: Allow the app to open

1. **Developer Mode:** on the iPhone open Settings, Privacy & Security, Developer Mode, turn it on and restart when asked.
   (The switch only shows after the first sideloaded app is installed.)
2. **Trust yourself as the developer:** Settings, General, VPN & Device Management, tap your Apple Account under
   *Developer App*, then **Trust**.
3. Open Rushify and connect it to your server.

#### Keeping it working

A free Apple Account app **expires after 7 days** and stops opening until it is signed again. You do not need to repeat the
computer steps each week. Use [SideStore](https://docs.sidestore.io/docs/installation/prerequisites) to look after it:

**Steps 2 and 3 are a one-time activity.** Do them once, using iloader to install SideStore on your iPhone (choose
SideStore in iloader instead of the Rushify IPA, or in addition to it). After that, **once you are signed in to SideStore with your
Apple Account, it refreshes your apps by itself every 7 days**, with no computer needed. Just keep LocalDevVPN connected
and your iPhone on Wi-Fi when a refresh is due.

**Installing a new version of Rushify later (no computer needed):**

1. On your iPhone, open the [Releases page](https://github.com/mandadapu28ster/rushify-ios/releases) in Safari and tap
   `Rushify-<version>.ipa` under **Assets** to download it.
2. Open SideStore, go to **My Apps**, tap **+**, and choose the downloaded `.ipa` (it is in the Files app, under Downloads).
3. Connect LocalDevVPN first. SideStore signs and installs the new version over the old one, and your settings and sign-in stay.

So you can skip Steps 2 and 3 for every future update. Apple also limits free accounts to a few apps and App IDs per week.

#### Sign-in errors

If iloader or SideStore will not accept your Apple Account, follow the community fix in
[SideStore discussion #1666](https://github.com/orgs/SideStore/discussions/1666#discussioncomment-19094443). In short:

- Switch SideStore to a different **anisette server** (Settings, Anisette Servers). The default one is the usual cause.
  Turning off *On-Device Anisette* first can help.
- Try again with your Apple ID and password. Use a dedicated Apple Account if you can.
- Still stuck? See [SideStore troubleshooting](https://docs.sidestore.io/docs/troubleshooting) or
  [iloader issues](https://github.com/nab138/iloader/issues).

#### Alternatives

- [Sideloadly](https://sideloadly.io/) or [AltStore](https://altstore.io/): same idea, different tool.
- **Xcode** (Mac): open the project, choose your iPhone, set your personal team under Signing & Capabilities and run.

Private repository: testers need read access to the repo to download release files.

### TestFlight (needs the paid Apple Developer Program)

If you join the Apple Developer Program, builds can be signed and uploaded to TestFlight so testers install through the TestFlight
app. That needs a distribution certificate, a provisioning profile and an App Store Connect API key stored as repository
secrets; the workflow can be extended with a signed archive and upload step.

## Notes

- The server address is usually plain `http://ip:port`, so App Transport Security allows arbitrary loads. The app warns and asks
  before connecting over HTTP, refuses an HTTPS-to-HTTP redirect, and shows a banner while connected insecurely. Use HTTPS when you can.
- The app icon is rendered by `scripts/make_icon.swift`.
