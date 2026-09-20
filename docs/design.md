# GPU Monitor — native Glass window

GPU Monitor uses the installed macOS design system: AppKit owns the window material, SwiftUI supplies native controls and content surfaces, and system fonts and SF Symbols supply the typography and icons. Menu bar geometry and monitoring behavior are unchanged.

## Observations and changes — 0.9.0

| Observed problem | Change |
| --- | --- |
| The previous window looked opaque even with a colorful separate window immediately behind it | Move Glass out of the SwiftUI background and make `NSGlassEffectView` the hosting controller’s root. Put the SwiftUI view in its supported `contentView` property |
| Color names repeated information already visible in each color chip, adding five button-shaped boxes | Use compact color swatches with an outer selection ring, like the system Appearance choices. Keep names in tooltips and accessibility labels |
| Several controls had both their native background and an additional custom Glass outline | Remove duplicate backings from segmented pickers, menus, header and footer. Preserve native focus and disabled states |
| Selected panels combined a color wash, gradient, multiple drawn rim strokes and shadow | Use native tinted Glass with an explicit menu-bar checkmark; remove simulated reflections and added shadows |
| Completely clear Glass allowed strong background text to compete with readings | Keep the window clear, but give content panels and reading wells progressively denser semantic backings |

## Window and content materials

`GlassHostingController` owns the material at the actual AppKit window boundary. On macOS 26+ it embeds the SwiftUI hosting view in `NSGlassEffectView.contentView` with the system clear Glass style. The independent window uses a transparent titlebar and background while retaining real window buttons, safe areas, resizing and frame restoration. The popover uses the same hosting controller.

The SwiftUI root knows when the native window already supplies Glass, so it does not place another full-window material over it. Server and log sheets use the system ultra-thin presentation material (macOS 13.3+) under their Glass content and controls, keeping native sheet sizing and dismissal. Older systems use a behind-window `NSVisualEffectView` with the popover material.

| Layer | Used for | Treatment |
| --- | --- | --- |
| Window | Dashboard and settings backdrop | Native clear Glass; receives the actual window behind it |
| Controls | Actions, pickers, menus, checkboxes and fields | Native styles and system focus, selection and disabled behavior |
| Panels | Servers, settings, input form, empty state | Native regular Glass with a 38% semantic neutral backing |
| Reading wells | GPU table, tmux sessions, pinned job and logs | Native regular Glass with a denser 58% semantic neutral backing |

Backing values describe a layer over the native material, not measured optical transparency. Text itself is never faded. A one-point inset leaves the native Glass edge visible without drawing a simulated reflection. Selected surfaces tint the native material with the chosen accent; the **메뉴바** checkmark and **고정** checkbox remain the explicit selection indicators.

## Controls, color and information

- Color choices are 24-point swatches with a 32-point selection ring and a 36-point button area. The monochrome choice uses a half-filled circle. Names remain available to VoiceOver and in tooltips.
- All actions use native Glass button styles where supported. Nonprimary buttons stay neutral so accent-colored symbols remain legible.
- Segmented pickers, checkboxes, menus, fields and linear progress views retain system behavior. Progress values are clamped, and an idle 0% bar has no colored fill.
- The chosen color immediately applies to window icons, GPU utilization and training progress. Errors and warnings retain semantic colors plus text.
- System text styles distinguish headings, readings, controls and supporting text. Numeric columns use monospaced digits. No font files are bundled.
- Settings remain compact. GPU readings stay aligned, and server/session disclosure, timestamps, progress scope, log access and visible **고정 / 감시 / 로그** controls remain available.
- Logs keep selectable monospaced text, wrapping, scrolling and a denser reading surface.

## Compatibility and accessibility

Native Liquid Glass requires macOS 26+ and Swift 6.2+. Older systems/toolchains use behind-window and standard SwiftUI materials with bordered controls, preserving the layout without trying to simulate refraction.

Reduce Transparency supplies opaque semantic surfaces and standard buttons; the native AppKit material also follows system accessibility behavior. Increased Contrast strengthens content boundaries. Selection is indicated by rings, checkmarks and control state in addition to color. No custom motion effects are added, so native controls manage their own system motion behavior.

## Validation

- Inspect the live native window over a separate four-color window with large background text. Check both actual backdrop transmission and legibility of the foreground content.
- Inspect settings swatches, accent propagation, server selection, add-server focus, log wrapping and sheet dismissal in the live native preview.
- Render synthetic light/dark dashboard, settings, add-server, logs, empty/error states, 4/8 GPUs, long names, 100% readings and minimum/default/wide windows.
- Run the 61 Python/Swift checks and native release build. Compile the older Swift compatibility path. CI tests and builds on macOS 14 and 26.

Accessibility branches are reviewed without changing the user’s global settings. Offscreen README images use synthetic data and compatibility materials; they do not reproduce actual behind-window optics. Native Glass is checked separately in a running window. This does not imply manual testing on every supported macOS version.

## References

- [Apple — NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
- [Apple — Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/)
- [Apple — Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple — Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [0.7.0 information and interaction audit](design-audit.md)
