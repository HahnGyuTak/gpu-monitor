# Interface design

GPU Monitor uses a quiet neutral palette with a blue accent. This is a design choice informed by platform conventions and visual hierarchy guidance, not a claim that one color is universally preferred.

## Principles and references

- [Apple — Typography](https://developer.apple.com/design/human-interface-guidelines/typography): use the macOS system font and a clear hierarchy. SwiftUI system text uses SF Pro for supported glyphs and the system fallback for Korean; no custom font is downloaded or bundled.
- [Apple — Color](https://developer.apple.com/design/human-interface-guidelines/color): adapt the presentation to light and dark appearances, and preserve the meaning of selection and status.
- [Nielsen Norman Group — 5 Principles of Visual Design](https://www.nngroup.com/articles/principles-visual-design/): use size, spacing, grouping and contrast to make important information easy to find. Muted text must remain readable.

## Applied choices

- Neutral gray canvas, solid cards, lightly inset GPU panels. Most text is neutral; blue is reserved for activity, selection and actions.
- 24 pt utilization readings, 19 pt app title, 12–13 pt primary interface text, and at least 11 pt secondary text. Logs alone use a monospaced face. Live numbers use monospaced digits to reduce horizontal movement.
- A shared four-segment identity for the app icon, server list and menu bar. The existing clockwise GPU order remains unchanged.
- Errors retain red/orange and explicit descriptions. GPU states have a tooltip with numbers and text; menu selection also has a checkmark. Color is not the sole status cue.
- Light/dark surfaces and secondary text colors are defined in `Appearance.swift`, rather than scattered through the interface.
- Larger click targets in the header and a labeled “서버 추가” action. The filter uses neutral selected surfaces and a selected accessibility trait.

| Role | Light | Dark |
| --- | --- | --- |
| Accent | `#245CD6` | `#8AB4FF` |
| Canvas | `#F3F4F6` | `#191A1E` |
| Card | `#FFFFFF` | `#24252A` |
| Inset panel | `#F4F5F7` | `#2C2D33` |
| Secondary text | `#5A606B` | `#ADB3BE` |

Preview images render the actual SwiftUI dashboard with synthetic data, with no SSH server names or logs from a user's machine. Their purpose is to review layout and appearance; they are not a usability study.

Regenerate the bundled app icon with `bash scripts/make-icon.sh`. The mark is drawn using AppKit paths; no third-party icon asset or font is embedded.
