# Liquid Glass dashboard

The popover uses a translucent canvas, readable material cards, and native Liquid Glass for the functional controls. The menu bar renderer, segment/bar layout, activity logic, and saved icon options are unchanged.

## References and interpretation

- [Blake Crosley — Liquid Glass SwiftUI patterns](https://blakecrosley.com/ko/blog/liquid-glass-swiftui-patterns): the article's HUD pattern informs the floating controls. It distinguishes controls from content and discusses transparency, stable digits, and reduced motion. GPU readings remain normal text; the app does not apply refracting text or mirrored numbers to monitoring data.
- [Apple — Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): `glassEffect` renders native glass; sibling controls share a `GlassEffectContainer`.
- [Apple — Materials](https://developer.apple.com/design/human-interface-guidelines/materials): glass is used for controls; server cards and logs use standard material.
- [Apple — Typography](https://developer.apple.com/design/human-interface-guidelines/typography): system fonts and a clear hierarchy, with monospaced digits for live values.

## Layers

The canvas uses `ultraThinMaterial` with a subtle, static tint derived from the selected color. Header actions, the filter and the add-server control use native regular glass on macOS 26+. Server cards use `regularMaterial`, with softly inset GPU panels. There is no continuously animated background.

The numeric hierarchy remains 24 pt utilization readings, a 19 pt app title, 12–13 pt primary text and at least 11 pt secondary text. Logs use a monospaced face. Errors and warnings retain their semantic red/orange descriptions.

## One color selection

`monitorTheme` distributes the existing `menuIconColor` through the SwiftUI environment. GPU utilization and training progress bars, header/server/GPU icons and action symbols use that color. Blue, the original green, orange, purple and appearance-aware monochrome are available. Inactive GPU segments remain neutral; color is also accompanied by values, tooltips or selection marks.

The selected color changes immediately in the dashboard and its sheets. No separate theme preference is stored. `GPUPieIcon.swift` and the menu bar update function have not been modified for this redesign.

## Compatibility and accessibility

- Native glass requires macOS 26+ and a build using Xcode 26+ / Swift 6.2+. Older systems and toolchains use the same control layout with standard material.
- Reduce Transparency uses opaque canvas, card and control surfaces.
- Reduce Motion disables the dashboard transition and the glass interaction effect.
- Increased Contrast adds stronger card outlines.
- The shape/color selection UI, keyboard actions, state descriptions and scrolling settings remain available.

The README images show synthetic data rendered through the compatibility material path. Live native glass is separately checked in the running app; its optical effect depends on the system and background and is not captured by the offscreen view bitmap renderer.

Regenerate the bundled app icon with `bash scripts/make-icon.sh`. That app icon and the existing menu bar icon assets are unchanged in this update.
