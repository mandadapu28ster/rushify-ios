# Rushify for iOS

Native SwiftUI client for the Rushify portfolio server. It is the iOS counterpart of the Android app
(`Rushify-Android`) and follows the same design: cache-first screens, one account's data never shown to
another, the password never stored (only the token, in the Keychain).

Requires iOS 17+, Xcode 16+.

## Status

Every screen of the Android app is ported.

| Area | State |
| --- | --- |
| Connect to a server (https, or http with a confirmation), sign in, session expiry, sign out, hide balances | done |
| Home: net worth, Investments, alerts (review symbols, dismiss), portfolio by sector, net worth by asset class, position size, net worth by broker, wealth over time, data freshness (web-style collapsible sections) | done |
| Holdings (account groups, lots, rollups, filters, search, sold lots, details), Pulse (radar, news, watchlists), Sync (Trading 212, SnapTrade, Monzo) | done |
| Performance & income (growth, benchmarks, dividends, daily equity), Corporate actions and symbols, Connections & keys, AI assistant, Change password | done |
| Add holding, edit lot, record sale, remove, edit values, sector override | done |

Navigation matches Android: three tabs (Home, Pulse, More); Holdings, Sync and the rest open from More.

## Build and test

```bash
brew install xcodegen
xcodegen generate            # creates Rushify.xcodeproj from project.yml
open Rushify.xcodeproj
```

Unit tests (about 415, against a stubbed network) and end-to-end tests (44, the real app driven through every screen):

```bash
xcodebuild test -project Rushify.xcodeproj -scheme Rushify \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RushifyTests -quiet
xcodebuild test -project Rushify.xcodeproj -scheme Rushify \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RushifyUITests -quiet
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

An iPhone only runs apps signed by Apple's system, so the `.ipa` is signed on your side with a free Apple ID:

- **Sideloadly** (Mac or Windows) or **AltStore**: download the `.ipa` from the release, connect the iPhone, sign in with your
  Apple ID in the tool and install. Turn on Developer Mode on the phone (Settings, Privacy & Security) and trust the
  developer profile (Settings, General, VPN & Device Management).
- **Xcode**: open the project, choose your iPhone, set your personal team under Signing & Capabilities and run.

A free Apple ID app expires after 7 days and has to be reinstalled (AltStore can refresh it automatically). Apple limits free
accounts to a few apps and App IDs per week. Private repository: testers need read access to the repo to download release files.

### TestFlight (needs the paid Apple Developer Program)

If you join the Apple Developer Program, builds can be signed and uploaded to TestFlight so testers install through the TestFlight
app. That needs a distribution certificate, a provisioning profile and an App Store Connect API key stored as repository
secrets; the workflow can be extended with a signed archive and upload step.

## Notes

- The server address is usually plain `http://ip:port`, so App Transport Security allows arbitrary loads. The app warns and asks
  before connecting over HTTP, refuses an HTTPS-to-HTTP redirect, and shows a banner while connected insecurely. Use HTTPS when you can.
- The app icon is rendered by `scripts/make_icon.swift`.
