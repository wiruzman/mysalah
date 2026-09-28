# MySalah app icon

Generated with the built-in image generation tool. The 1024-pixel RGBA master is
`App/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. The original generated
artwork was resized using macOS `sips`; the transparent surround is preserved.
Run `./scripts/generate-app-icon.sh` to derive the six smaller PNGs. The ten macOS
1×/2× slots share files where their pixel dimensions match.

The asset catalog is part of the app's resources and `AppIcon` is selected in
both build configurations. Xcode supplies the compiled icon and its Info.plist
metadata. This artwork does not replace the status item's SF Symbol.

The artwork was refined after a Finder comparison: the original tile's bounds
already matched Music closely (104 versus 102 pixels at 128-pixel resolution,
using 50% alpha), but its dark inset rim made it appear smaller. The current
version has a clearer blue perimeter, a shallower rim, and a larger crescent.
Its 50%-alpha bounds are 106 × 106 pixels at 128-pixel resolution. The original
artwork remains available in commit `daac7a4`.

## Generation prompt

```text
Use case: logo-brand
Asset type: production macOS application icon for MySalah, a quiet native Muslim prayer-times menu-bar app whose existing symbol is a crescent moon.
Primary request: Create one beautifully finished, understated macOS app icon: a single bold sculpted ivory crescent moon on a deep midnight-blue rounded-square tile. The crescent opens toward the upper right and has a strong, instantly legible silhouette. Its softly bevelled porcelain surface catches cool white light on the upper left, with a subtle warm ivory lower edge. Center the crescent optically with generous breathing room; it occupies about 58 percent of the tile height. The tile has restrained depth, a very subtle blue light near its center, smooth corners and a fine soft edge highlight. Calm, precise and premium native macOS design, minimal and harmonious.
Composition/framing: single front-facing icon, straight-on orthographic view, centered on a square 1024 by 1024 canvas. Rounded-square tile spans approximately x=100..924 and y=100..924, with corner radius around 180. Transparent outside the tile, with only a compact soft shadow. No surrounding scene. The moon must remain crisp and recognizable at 16 and 32 pixels.
Constraints: no text, letters, numerals, clock hands, stars, mosque, decorative patterns, border frame, mockup, extra icons, watermark, perspective tilt, or checkerboard pattern. Actual alpha transparency outside the tile. Deliver just the final icon artwork.
```

## Optical-size refinement prompt

Applied with the built-in image generation tool, using the original 1024-pixel
icon as the edit target and preserving transparency.

```text
Use case: precise-object-edit
Asset type: MySalah macOS app icon, optical size correction.
Input image: existing approved MySalah app icon, edit target. Preserve its identity, ivory sculpted crescent, crescent orientation opening upper-right, rounded-square silhouette, midnight-blue family, front-on composition, no text.
Change only the optical weight so the icon does not look smaller beside other macOS app icons. Keep the outer rounded-square tile and its position at the same dimensions as the reference (approximately 82% of the square canvas, centered). Remove the broad near-black inset bevel/rim: extend the visible blue face smoothly to a clear thin rounded-square edge, using a slightly brighter restrained sapphire blue at the perimeter, with very shallow depth instead of a thick dark lip. The bottom and right edges must remain clearly visible on a dark gray Finder background. Enlarge the existing ivory crescent about 10% about its optical center while preserving its exact silhouette, orientation, porcelain material and lighting. Keep generous space around its tips. Avoid excessive gloss, glow, new ornament or a border stroke. The result should feel the same icon, with more immediate legibility at 32 pixels.
Output a single square production icon, ideally 1024 by 1024, with real transparent alpha outside the tile and a very compact subtle shadow. Do not add a mockup, text, stars, clock, backdrop or checkerboard.
```
