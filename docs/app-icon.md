# MySalah app icon

Generated with the built-in image generation tool. The 1024-pixel RGBA master is
`App/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. The original generated
artwork was resized using macOS `sips`; the transparent surround is preserved.
Run `./scripts/generate-app-icon.sh` to derive the six smaller PNGs. The ten macOS
1×/2× slots share files where their pixel dimensions match.

The asset catalog is part of the app's resources and `AppIcon` is selected in
both build configurations. Xcode supplies the compiled icon and its Info.plist
metadata. This artwork does not replace the status item's SF Symbol.

## Generation prompt

```text
Use case: logo-brand
Asset type: production macOS application icon for MySalah, a quiet native Muslim prayer-times menu-bar app whose existing symbol is a crescent moon.
Primary request: Create one beautifully finished, understated macOS app icon: a single bold sculpted ivory crescent moon on a deep midnight-blue rounded-square tile. The crescent opens toward the upper right and has a strong, instantly legible silhouette. Its softly bevelled porcelain surface catches cool white light on the upper left, with a subtle warm ivory lower edge. Center the crescent optically with generous breathing room; it occupies about 58 percent of the tile height. The tile has restrained depth, a very subtle blue light near its center, smooth corners and a fine soft edge highlight. Calm, precise and premium native macOS design, minimal and harmonious.
Composition/framing: single front-facing icon, straight-on orthographic view, centered on a square 1024 by 1024 canvas. Rounded-square tile spans approximately x=100..924 and y=100..924, with corner radius around 180. Transparent outside the tile, with only a compact soft shadow. No surrounding scene. The moon must remain crisp and recognizable at 16 and 32 pixels.
Constraints: no text, letters, numerals, clock hands, stars, mosque, decorative patterns, border frame, mockup, extra icons, watermark, perspective tilt, or checkerboard pattern. Actual alpha transparency outside the tile. Deliver just the final icon artwork.
```
