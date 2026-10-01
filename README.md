# MySalah

MySalah puts Muslim prayer times in the macOS menu bar. A moon and minutes countdown lead to a compact native menu showing the day's timetable, the active prayer, and checked, nested settings.

## Features

- Diyanet's published Fajr, sunrise, Dhuhr, Asr, Maghrib, and Isha times, supplied through [EzanVakti](https://ezanvakti.emushaf.net/).
- Country → region/city → district selection from the provider's supported locations. The timetable header displays the selected district and country. Some countries have one country-wide region; choose the town in its district submenu.
- Optional locally calculated Hanafi Asr, with all other times unchanged.
- A checked **Calculation method → Diyanet** submenu. Diyanet is currently the only timetable method; **Asr calculation** remains a separate setting.
- English, Danish, Turkish, and Arabic; system language by default, English fallback, and mirrored Arabic prayer rows.
- System/light/dark themes and system/12/24-hour clocks.
- Prayer rows show the name, then the active prayer's seconds countdown in a vertically centered pill immediately before its start time; Arabic mirrors the columns. The menu bar shows rounded-up remaining minutes only from 59m down to 1m; otherwise it shows just the moon.
- Prayer-start notifications and optional 15/30/45-minute reminders before each prayer ends. Set all five together or customize them individually.
- Cached offline timetables and optional Launch at Login, disabled initially.
- No account, backend, Dock icon, device-location permission, or analytics.

## Download and install

Compiled builds are distributed through [GitHub Releases](https://github.com/wiruzman/mysalah/releases). Download the **MySalah-v…-macOS.zip** release asset, rather than a Source code archive. Each release supports macOS 14 or later on both Apple Silicon and Intel.

Unzip the download, quit any running copy of MySalah, and move **MySalah.app** to **/Applications**. Open it and look for the moon in the menu bar. To update, replace the existing app in that same folder; preferences and cached timetables are preserved. Keep only one installed copy.

**These builds are ad-hoc signed and are not notarized by Apple.** macOS may block the first launch because it cannot verify the developer or check the app for malicious software. If you trust the download, attempt to open it once, then choose **System Settings → Privacy & Security → Open Anyway** and confirm. See [Apple's instructions for opening an unnotarized app](https://support.apple.com/en-us/102445). Managed Macs may prohibit this override.

Each ZIP has a matching `.sha256` asset. Download both into the same directory, then run `shasum -a 256 -c MySalah-vVERSION-macOS.zip.sha256`, replacing `VERSION` with the downloaded version. This checks download integrity; it does not provide Apple notarization.

## Getting started

Launch MySalah, click the moon, and choose **Location**. The app resolves the selected town's coordinates and timezone through Apple geocoding. If Apple finds multiple matches, select one under **Confirm location**. No timetable notifications are scheduled until a valid location and timetable are available.

The first valid configuration requests notification permission if notifications are enabled. You can change this later from **Prayer-start notifications → Open Notification Settings**. macOS Focus and notification settings control how alerts appear and sound.

Enable **Developer Mode → On** to reveal **Test Notifications**. Developer Mode defaults to Off, persists across launches, and hides the test menu when disabled. Use **Test Notifications → prayer → notification type** to check each prayer-start alert and its 15/30/45-minute end reminders immediately. Test alerts are marked “Test” and use the app's current language and normal alert wording. They work without a selected location and with regular alerts turned off, but require existing macOS notification permission. Tests do not request permission, change preferences, or replace scheduled prayer alerts; each test replaces the previous test notification. Focus and macOS notification settings still apply.

All settings persist and apply immediately. **Before prayer ends → All prayers** replaces the five individual reminder values; changing one afterward makes the shared setting **Custom**. Sunrise remains informational and does not have its own alert.

The theme affects the dropdown; the template moon follows the system menu bar's contrast. Launch at Login is managed through macOS Service Management and can require approval under System Settings → General → Login Items.

## Prayer-time behavior

Fajr counts down to sunrise. Between sunrise and Dhuhr there is no highlighted prayer; the header counts down to Dhuhr. Dhuhr ends at the selected Asr time, Asr at Maghrib, Maghrib at Isha, and Isha at the following Fajr. Before dawn, the active Isha row shows the preceding timetable's start and a **Yesterday** label. Missing adjacent-day data is not guessed.

EzanVakti is a third-party distributor of Diyanet data, not Diyanet's authenticated API. Its documented timezone fields are unreliable internationally. MySalah combines Gregorian dates and published clock strings with the selected location's IANA timezone, independent of the Mac's timezone. `Gunes` is the published sunrise/Fajr-end boundary; it differs from the additional astronomical sunrise field.

**Hanafi Asr is calculated, not an official Diyanet timetable value.** MySalah uses [Adhan Swift 1.5.0](https://github.com/batoulapps/adhan-swift/tree/1.5.0), shadow factor two, upward minute rounding, and no manual Asr adjustments. Only its Asr result is used. Invalid or unavailable calculations display an unavailable Asr rather than silently substituting the earlier time. Coordinates are the Apple-resolved town location, which can differ from a provider's exact calculation point.

Timetables refresh when stale after 24 hours or when current/next-day coverage is insufficient. The normal timetable footer shows only **Cached timetable · updated [time]**. Loading and error states display their relevant status instead. Valid cached dates remain usable offline; expired dates are never shown as today's timetable. A failed refresh retries after 30 seconds, 2 minutes, 10 minutes, and 1 hour; manual **Refresh/Retry** is also available.

The app schedules at most 60 future notifications from verified coverage. Already scheduled alerts can be delivered when MySalah is not running, but launch it regularly—or enable Launch at Login—to refresh the rolling schedule. Wake does not replay missed alerts, and macOS can defer delivery while asleep or in Focus.

## Development

Requirements: macOS 14+, Xcode 16+ with Swift 6, the Xcode command-line tools, and network access for the initial dependency fetch. Development was verified with Xcode 27. The deployment target remains macOS 14.

Open `MySalah.xcodeproj`, select the shared **MySalah** scheme, and Run. Local builds use ad-hoc signing; no Apple Developer subscription is needed. The app appears in the menu bar, not the Dock.

```sh
# Fast deterministic core tests
swift test

# Core + native app/model/menu tests and offscreen UI renders
xcodebuild -project MySalah.xcodeproj -scheme MySalah \
  -configuration Debug -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' test

# Native tests with optional Apple geocoder + live Copenhagen/Istanbul API checks
MYSALAH_LIVE_TESTS=1 ./scripts/test-app.sh
```

Core tests use clock inputs, URLProtocol stubs, and API responses captured on 28 September 2026. App tests use isolated preferences/cache directories and mock notification permission; they do not enable your login startup or request notification authorization. Rendered panel images are written to `build/previews`. Check VoiceOver, keyboard menu tracking, system appearance changes, and real notification delivery manually when changing related behavior.

The core Swift package owns domain logic; AppKit/SwiftUI and OS services live in `App`. See [AGENTS.md](AGENTS.md) for development conventions and timing invariants. Dependencies are pinned in the checked-in lockfiles. MIT notices are bundled and available through **About MySalah**.

The application icon is an ivory crescent on a midnight-blue tile. Its artwork source lives in `App/Assets.xcassets/AppIcon.appiconset`; both Debug and Release bundles include the complete standalone `App/MySalah.icns` icon with an explicit `CFBundleIconFile` reference for Finder, About, and notifications. The menu bar continues to use the native template moon. After editing the 1024-pixel master, run `./scripts/generate-app-icon.sh` to regenerate smaller PNGs and the ICNS file. See [the artwork notes](docs/app-icon.md) for the source prompt.

## Build and install locally

```sh
./scripts/build-local.sh
./scripts/install-local.sh --system --launch
```

The release bundle is produced at `build/DerivedData/Build/Products/Release/MySalah.app` and the installer defaults to `/Applications/MySalah.app` (`--system` remains supported). The installer verifies signing, stages the new bundle, and refuses to replace an app that is still running. Without `--launch`, it only installs. Rebuild before installing source changes.

Installation requires write access to `/Applications`. Keep this location when using Pelmet or Hidden Bar on macOS 27. When migrating an existing installation, quit MySalah and move `~/Applications/MySalah.app` to `/Applications` in Finder first, so there is only one installed copy. Preferences and cached timetables stay in your home Library. Check Launch at Login after changing the installation path if you previously enabled it.

Local and GitHub builds use ad-hoc signing. They can be distributed without an Apple Developer membership, with the first-launch limitations described above. Developer ID signing and Apple notarization would require membership. App Store distribution is outside the current setup.

## Creating a GitHub release

The release workflow in `.github/workflows/release.yml` runs when a tag matching `v*` is pushed. It accepts stable versions in the form `vMAJOR.MINOR.PATCH`, such as `v1.0.0`, and rejects other formats. It uses the macOS 15 runner with Xcode 26.3, runs the offline SwiftPM and native Xcode tests, then builds and verifies a universal ZIP with a SHA-256 checksum. Both dependency lockfiles remain authoritative.

After committing and pushing the intended source changes, tag that commit and push the tag:

```sh
git tag -a v1.0.0 -m "MySalah 1.0.0"
git push origin v1.0.0
```

Use a new version for each release. A successful workflow creates a **draft** GitHub Release containing the ZIP, checksum, installation guidance, and generated change notes. Review the draft and download its ZIP for a first-launch smoke test before choosing **Publish release**. The workflow uses GitHub's built-in token with `contents: write`; no Apple credentials or additional repository secrets are needed. It fails if that release already exists rather than replacing published assets. If a failed upload left an incomplete draft, delete only that draft before rerunning the workflow, retaining the tag.

To exercise packaging locally without creating a tag or GitHub Release:

```sh
./scripts/package-release.sh v1.0.0 1
```

The optional second argument is the positive build number (default `1`; CI uses its workflow run number). The app's version comes from the tag. Output is written to `build/releases/v1.0.0/`, using separate build products in `build/ReleaseDerivedData`. Packaging checks both CPU architectures, bundle version, dependency notices, and the ad-hoc signature before and after ZIP extraction. It does not install or launch the app.

Automated tests and archive verification do not replace manual testing of a browser-downloaded copy through Gatekeeper, Intel execution, macOS 14 compatibility, notifications, or Launch at Login.

## Troubleshooting and local data

- **Icon disappears when Pelmet or Hidden Bar hides other apps on macOS 27:** run MySalah from `/Applications`, rather than `~/Applications` or Xcode's build folder. The system's menu bar hiding mechanism can fail to recognize apps outside that location even when a manager marks them visible; see [Pelmet's investigation](https://github.com/fif7y/pelmet/issues/30). Quit MySalah, move the installed bundle, and relaunch it from the new location. This is an installation workaround; the app does not override the manager's visibility choices.
- **No times:** choose a location, then Refresh. Location lookup needs Apple geocoding access; prayer data needs `ezanvakti.emushaf.net`. The app never substitutes the device timezone if location resolution fails.
- **Saved/offline times:** the provider could not be reached. Current cached dates still work; retry when connected.
- **No alerts:** check the app's notification choices, macOS notification permission, and Focus. End reminders are skipped if the chosen interval would fall before that prayer starts.
- **Blank notification icon after local updates:** a restart resolved the observed placeholder on macOS 27 after installing the updated app. Try a fresh alert from **Test Notifications** after restarting. Notification appearance must be checked in macOS; automated icon tests only verify the packaged artwork.
- **Login startup needs approval:** use the approval item in the Launch at Login submenu, then check macOS Login Items. Install in a stable Applications folder before enabling it.
- **Native tests and macOS versions:** offscreen UI tests do not replace a real VoiceOver/notification/login smoke test. macOS 14 API compatibility is enforced by the deployment target; testing on a macOS 14 machine remains separate from testing the current OS.

Preferences use the `com.mehmet.mysalah` UserDefaults domain. Timetables, supported-place lists, and geocoded town metadata are stored under `~/Library/Application Support/MySalah`. Only your chosen town names are sent to Apple geocoding and provider location identifiers to EzanVakti. The application never reads your device's precise location.

## License and attribution

MySalah is [MIT licensed](LICENSE.md), © 2026 Mehmet. Adhan Swift is MIT licensed by Batoul Apps; its full notice is included in `App/ThirdPartyNotices.txt` and every app bundle. Prayer timetable attribution belongs to Diyanet and EzanVakti; MySalah is an independent application.
