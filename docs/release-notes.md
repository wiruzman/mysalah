## Download and install

Download the **MySalah-v…-macOS.zip** asset below (the **Source code** archives are for developers). Requires macOS 14 or later; the app includes both Apple Silicon and Intel support.

1. Unzip the download.
2. Quit any running copy of MySalah, then move **MySalah.app** to **/Applications**, replacing the previous copy if updating. Preferences and cached timetables are preserved.
3. Open MySalah. It appears as a moon in the menu bar, with no Dock icon.

**This release is ad-hoc signed and is not notarized by Apple.** macOS may block its first launch because it cannot verify the developer or check the app for malicious software. If you trust this download, attempt to open it once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. See [Apple's instructions](https://support.apple.com/en-us/102445). Managed Macs may prohibit this override.

The accompanying `.sha256` file lets you check the ZIP for download corruption. From the directory containing both files, run `shasum -a 256 -c MySalah-vVERSION-macOS.zip.sha256`, replacing `VERSION` with this release's version. A matching checksum is not Apple notarization.
