# GPU Monitor — continuous Glass surfaces

The same Glass material family now spans the window canvas, navigation, server panels, settings, input sheets and logs. Each layer has its own density so the window remains translucent while readings stay legible. Native controls retain their keyboard, selection and disabled behavior.

## Surface hierarchy

| Layer | Used for | Readability treatment |
| --- | --- | --- |
| Canvas | Window and sheet backgrounds | Behind-window system material and a light neutral backing |
| Controls | Header, filters, footer, menus and color choices | Clearer glass with a subtle reflecting edge |
| Panels | Servers, settings sections, server input form, empty state | Frosted glass that separates groups from the canvas |
| Reading wells | GPU table, tmux sessions, pinned job and log text | Denser neutral backing to reduce transmission behind text |

`MonitorGlassSurface` owns this hierarchy. On macOS 26+ it uses native `glassEffect(.regular, in:)`. A neutral fill is composited **over the material and behind content**: 12%, 22%, 34% and 58% for the four layers. These are backing opacities, not a claim about the optical transparency of the system material. Text itself is never faded to achieve a glass effect.

The canvas includes an AppKit `NSVisualEffectView` with behind-window blending. The independent window has a transparent titlebar and full-size content background while retaining the native title, window buttons, safe area and resize behavior. Neither the desktop nor the titlebar is recreated as a bitmap.

## Selected server

The selected server uses a lightly accent-tinted native glass surface, an understated color wash and translucent edge bands that fade inward. A directional highlight gives the surface a reflective rim. It no longer uses a uniform accent-colored outline. The **메뉴바** checkmark remains the explicit selection indicator; pinned jobs use the same material treatment and retain their **고정** checkbox.

No selection animation, external glow or continuously moving effect is added. The small panel shadow separates surfaces; reading wells do not add another shadow.

## Controls and information

- The GPU table remains aligned in rows. Utilization, VRAM and temperature use monospaced digits; `100%` remains on one line.
- Header, row, retry, log and sheet actions share native glass button styles. Nonprimary glass stays neutral so accent-colored symbols remain legible.
- Segmented pickers, checkboxes, text fields and menus preserve native semantics and focus behavior. They sit on the shared glass control/form surfaces.
- Server and session disclosures, visible **고정 / 감시 / 로그** actions, error text, timestamps and progress scope remain available.
- Settings retain aligned controls within compact glass sections. Main preferences fit the default window without scrolling.
- Log text has the densest backing, system monospaced type, selection/copy, wrapping and scrolling.

The system font is used throughout: `headline` for titles, `body`/`callout` for readings and controls, `caption` for supporting text and `title3` for progress. No font assets are bundled. The existing user-selected icon color supplies GPU/progress bars, content icons and selection glass. Errors and warnings keep their semantic colors and text.

## Compatibility and accessibility

Native Liquid Glass requires macOS 26+ and Swift 6.2+. Older systems/toolchains use standard regular/thick system materials and bordered controls in the same layout. They do not reproduce native glass refraction.

Reduce Transparency removes behind-window transparency and native glass, fills surfaces opaquely and uses standard controls. Increased Contrast strengthens surface boundaries. Text and selection indicators remain explicit. There are no custom motion effects; native control motion is managed by the OS.

## Validation — 0.8.0

- Native build plus older Swift compatibility compilation.
- 61 Python/Swift checks covering collection, job transitions, refresh, guarded deletion, preferences, filters and menu icon rendering.
- Synthetic light/dark rendering of dashboard, settings, add-server, logs, empty/error states, 4/8 GPUs, long names, 100% readings, minimum/default/wide windows.
- Running-app inspection of the glass canvas, titlebar, selected-server tint/edges, settings and readable log surface. SSH input focus, Escape dismissal and standard controls remain available.
- macOS 14 and 26 CI run tests, build the app and verify its signature.

Accessibility fallbacks are reviewed in code; this check does not change global system accessibility preferences. README screenshots use synthetic data and compatibility materials. Native glass and behind-window optics are separately checked in the running app and are not fully reproduced by an offscreen bitmap.

Menu bar icon geometry, activity logic, saved shape/color choices and remote job behavior are unchanged. The resizable window, frame restoration and standard `⌘0`, `⌘W`, `⌘M`, `⌘R`, `⌘N`, `⌘,`, `⌘Q` actions remain available.

## References

- [Apple — Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple — Glass](https://developer.apple.com/documentation/swiftui/glass)
- [Apple — Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [0.7.0 information and interaction audit](design-audit.md)
