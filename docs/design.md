# GPU Monitor design

The dashboard is a compact monitoring list. Controls use native macOS behavior; server readings remain on neutral, opaque system surfaces. A server is one visual group, with GPU readings aligned in rows and tmux sessions below them. The menu bar renderer is independent of this layout.

## Information and controls

- The header contains navigation and global actions. A native segmented picker filters jobs; GPU readings remain server-wide.
- Each server header contains its name, connection/refresh state, menu bar selection and management menu. Names truncate in the middle and expose their full value in a tooltip.
- GPU rows share columns for index/name, utilization, VRAM and temperature. Numeric values use monospaced digits; bars are supplementary, not the sole status indication.
- Sessions use disclosure buttons and row separators. Only the pinned job receives a selection background. **고정**, **감시** and **로그** have visible labels; selection uses native checkboxes.
- Settings use aligned fields, section headings and separators. Supporting observation details sit in a disclosure group. No nested material cards are needed.
- SSH setup uses standard text fields with focus rings, a labelled alias menu, a native target picker and explicit cancel/submit actions. Logs use a selectable monospaced text surface with wrapping, copy, refresh and end navigation.

## Typography and color

Use the system font without additional font assets: `headline` for server/section titles, `body`/`callout` for readings and controls, `caption` for secondary details and `title3` for training progress. Log content uses the system monospaced font. GPU values share trailing alignment.

`NSColor.windowBackgroundColor`, `controlBackgroundColor`, `textBackgroundColor`, `secondaryLabelColor` and `separatorColor` define neutral surfaces and text roles. The existing icon color preference supplies the accent for GPU/progress bars and content icons. Error and warning states retain semantic colors and explicit text. Selected controls also have a checkmark or native selection treatment. Disabled icon actions use `disabledControlTextColor`.

## Materials and motion

On macOS 26+ with Swift 6.2+, functional header and sheet buttons use native `.glass`/`.glassProminent` styles within `GlassEffectContainer`. Nonprimary buttons keep a neutral glass surface so accent-colored symbols remain legible. Content, logs, GPU rows and settings sections do not stack glass effects, gradients or shadows.

Older systems/toolchains and Reduce Transparency use standard bordered buttons in the same layout. System surfaces are already opaque. Increased Contrast strengthens server outlines. There are no custom entrance or continuous animations; native controls handle their own motion and focus behavior.

## macOS behavior

The menu bar popover is 520 × 700. Its **윈도우** action opens a resizable independent window with a minimum content size of 520 × 420. The window saves its frame and is reused when reopened. Native window buttons and the AppKit Window/Edit menus provide standard close, minimize, selection and clipboard behavior.

- `⌘0`: open the monitor window while the app is active.
- `⌘R`, `⌘N`, `⌘,`: refresh, add a server, switch settings.
- `⌘W`, `⌘M`, `⌘Q`: close, minimize, quit.
- Return submits a valid server form; Escape dismisses a sheet.

Dashboard/settings navigation preserves expansion and scroll state. Hidden content does not receive input or accessibility focus. Log sheets follow a stable pane identity even when a job leaves the current filter. Destructive actions retain their native confirmations and remote fresh-state validation.

## References and validation

- [Apple — Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple — Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Apple — Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Blake Crosley — Liquid Glass SwiftUI patterns](https://blakecrosley.com/ko/blog/liquid-glass-swiftui-patterns)

The [0.7.0 audit](design-audit.md) records observable problems and the resulting changes. README images use synthetic data rendered with the compatibility controls. Native glass is checked separately in the running app; an offscreen bitmap does not reproduce its optical effects. System accessibility preferences are handled through native behavior/shared modifiers; changing those system settings is not part of the manual test.

Menu bar circle/barcode rendering, the bundled app icon and saved icon preferences are preserved. Circles cover 1–8 GPUs clockwise from 12 o’clock; counts above eight have no special handling.
