# Liquid Glass dashboard

The popover uses a translucent canvas, readable material cards, and native Liquid Glass for the functional controls. Menu bar circles represent 1–8 GPUs in a single circle, in clockwise GPU order from 12 o’clock. The barcode layout, activity logic and saved icon options are preserved. Counts above eight have no special handling.

## References and interpretation

- [Blake Crosley — Liquid Glass SwiftUI patterns](https://blakecrosley.com/ko/blog/liquid-glass-swiftui-patterns): the article's HUD pattern informs the floating controls. It distinguishes controls from content and discusses transparency, stable digits, and reduced motion. GPU readings remain normal text; the app does not apply refracting text or mirrored numbers to monitoring data.
- [Apple — Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): `glassEffect` renders native glass; sibling controls share a `GlassEffectContainer`.
- [Apple — Materials](https://developer.apple.com/design/human-interface-guidelines/materials): glass is used for controls; server cards and logs use standard material.
- [Apple — Typography](https://developer.apple.com/design/human-interface-guidelines/typography): system fonts and a clear hierarchy, with monospaced digits for live values.

## Layers

The canvas uses `ultraThinMaterial` with a subtle, static tint derived from the selected color. Header actions, segmented choices, sheet actions and log controls use native regular glass on macOS 26+. Embedded row actions share 30 pt hit targets and a consistent hover/pressed/selected treatment without stacking more glass on the data. Header icon actions have 36 pt targets. Settings use the same material section cards and spacing as the dashboard; sheets share a title, supporting text and close control. Server cards use `regularMaterial`, with softly inset GPU panels. There is no continuously animated background.

The numeric hierarchy remains 24 pt utilization readings, a 19 pt app title, 12–13 pt primary text and at least 11 pt secondary text. Logs use a monospaced face. Errors and warnings retain their semantic red/orange descriptions.

## One color selection

`monitorTheme` distributes the existing `menuIconColor` through the SwiftUI environment. GPU utilization and training progress bars, header/server/GPU icons and action symbols use that color. Button text stays neutral for legibility with all five accents. Blue, the original green, orange, purple and appearance-aware monochrome are available. Inactive GPU segments remain neutral; color is also accompanied by values, tooltips or selection marks.

The selected color changes immediately in the dashboard and its sheets. No separate theme preference is stored. The menu bar update function uses the same saved color and shape selection.

## Compatibility and accessibility

- Native glass requires macOS 26+ and a build using Xcode 26+ / Swift 6.2+. Older systems and toolchains use the same control layout with standard material.
- Reduce Transparency uses opaque canvas, card and control surfaces.
- Reduce Motion disables the dashboard transition and the glass interaction effect.
- Increased Contrast adds stronger card outlines.
- The shape/color selection UI, keyboard actions, state descriptions and scrolling settings remain available.

The README images show synthetic data rendered through the compatibility material path. Live native glass is separately checked in the running app; its optical effect depends on the system and background and is not captured by the offscreen view bitmap renderer.

Regenerate the bundled app icon with `bash scripts/make-icon.sh`. The bundled app icon remains unchanged. Menu bar status icons are rendered from the current GPU state.

## Interaction audit — 0.6.0

- Dashboard and settings keep their scroll and expansion state across navigation. Hidden screens do not receive input or accessibility focus.
- Server and session headings toggle the full group. Server removal has a native destructive confirmation; remote tmux deletion retains its existing fresh-state check.
- Empty, paused, failed and unavailable states have distinct messages. A healthy tmux response with no server is an empty session list, not a missing installation. Last-known readings remain legible after a transport failure.
- The log sheet observes current state, follows the requested pane identity, supports wrapping/copy/refresh/end navigation and survives changes to the running filter. The sheet belongs to the stable server card, not the transient job row.
- SSH setup labels fields explicitly and provides automatic/host/Docker choices. Whitespace-only input cannot submit. Return submits and Escape dismisses.
- Cmd-R, Cmd-N and Cmd-comma are scoped to the visible interface. A standard AppKit Edit menu restores the responder-chain text shortcuts; Cmd-Q quits.
- Notification authorization has a pending state to prevent overlapping requests. The test action is disabled until notifications are enabled.

Validation includes 61 Python/Swift checks, native and compatibility builds, synthetic light/dark renders for dashboard/settings/add/log/empty/error screens, and hands-on checks in the running app. Native menus and confirmation sheets use system rendering. Remote training jobs are not stopped or removed during UI checks. Reduce Motion, Reduce Transparency and Increased Contrast are handled in the shared modifiers; system accessibility settings are not changed as part of the audit.
