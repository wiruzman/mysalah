# Development guidelines

MySalah is a Swift 6 menu bar application for macOS 14 and later. Preserve its native AppKit menus and SwiftUI prayer panel. Settings belong in checked, nested menus; do not introduce a separate settings dashboard.

## Architecture

- `Sources/MySalahCore`: platform-independent models, EzanVakti decoding, date parsing, Hanafi Asr, schedule and notification planning, localization, persistence.
- `App`: main-actor application coordination, AppKit status menus, SwiftUI content, Apple geocoding, UserNotifications, and Service Management adapters.
- `Tests/MySalahCoreTests`: deterministic unit tests and captured public API fixtures. These run with SwiftPM and Xcode.
- `Tests/MySalahAppTests`: native adapter/model/menu tests, offscreen panel rendering, and opt-in live checks. Xcode compiles the app support sources into its hostless test target.

Keep provider, clock, geocoder, and notification boundaries injectable. Keep network requests asynchronous. Cancel obsolete work and verify request identity after suspension before applying results. Never mutate UI off the main actor. Do not add dependencies without a concrete need; Adhan Swift is pinned exactly to 1.5.0 in both package lockfiles.

## Timing invariants

- The selected locality's IANA timezone is authoritative. Never interpret provider clock strings in the device timezone or trust the provider's GMT/ISO offset fields.
- Use Gregorian calendar arithmetic for dates, especially across daylight-saving changes. Never obtain tomorrow by adding 86,400 seconds.
- Fajr ends at the published `Gunes` value. Sunrise is not an obligatory prayer and has no prayer-start alert.
- Between sunrise and Dhuhr there is no active prayer. Isha requires a verified next-day Fajr boundary; never bridge missing calendar dates.
- Before dawn, the active Isha belongs to the preceding timetable date. Northern summer Isha may itself occur after civil midnight.
- Hanafi replaces only Asr with Adhan's shadow-factor-two result, rounded upward, without manual offsets. Missing/invalid results must not silently fall back to the published Asr.
- UI and notifications must use the same schedule engine. Never invent coverage or use expired dates as today's schedule.
- Notifications must be future-only, deduplicated, capped at 60, and replaced after relevant preferences change. Do not replay missed events after wake.

## Interface and localization

Use semantic native colors, system fonts, SF Symbols, and monospaced digits. Keep the prayer highlight independent of menu hover. Mirror prayer columns for Arabic and keep durations readable. All user-visible text belongs in the four `Localizable.strings` files. Add every key and matching format placeholders to English, Danish, Turkish, and Arabic. English is the fallback; do not translate proper place names beyond names supplied by the provider.

Maintain VoiceOver labels, keyboard menu navigation, sufficient contrast, and Reduce Motion/Transparency compatibility. Do not continuously announce seconds to VoiceOver. Run seconds updates only while the menu is open, including the event-tracking run-loop mode.

Prayer rows place the name first, flexible space, the countdown, then the start time. Keep the countdown vertically centered in a contrasting capsule beside the start time, never before the prayer name. Mirror that column order for Arabic.

The menu bar minute badge appears only when its rounded-up value is 1–59 minutes. At 60 minutes or more, or without a future boundary, show only the moon. This threshold does not affect the countdown inside the menu.

## Build and validation

```sh
swift test
xcodebuild -project MySalah.xcodeproj -scheme MySalah -configuration Debug \
  -derivedDataPath build/DerivedData -destination 'platform=macOS' test
./scripts/build-local.sh
```

The Xcode suite renders all four languages in light/dark into `build/previews`. Inspect relevant renders when changing UI. Run the optional service smoke test with `MYSALAH_LIVE_TESTS=1 ./scripts/test-app.sh`; ordinary tests must remain offline. Verify date boundaries, missing data, cache expiry, network failure, permission denial, and overlapping location requests for related changes. Never change the user's location, notification permission, or login preferences just to run tests; use isolated stores and mocks.

Keep the checked-in Xcode project and shared scheme current when adding app or test files. Keep build artifacts and user Xcode state untracked. Update README for behavior/build changes and preserve dependency notices in the app bundle. Clearly distinguish automated validation from manual OS-level checks that have not been performed.

## Local installation

On macOS 27 with Pelmet or Hidden Bar, install and run MySalah from `/Applications/MySalah.app`, not `~/Applications` or Xcode's DerivedData. Moving this installation to `/Applications` resolved the confirmed issue where the system hid MySalah despite the manager marking it visible. Preserve this location for updates; do not create a second installed copy in `~/Applications`.

Rebuild with `./scripts/build-local.sh`, quit the running MySalah app, then install with `./scripts/install-local.sh --system --launch`. Preserve the user's preferences and cached data. Verify that the moon remains visible when the menu bar manager collapses after changes affecting installation or status-item registration.
