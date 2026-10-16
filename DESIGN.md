# SovietExtension Design System

## 1. Atmosphere & Identity

SovietExtension uses compact, native macOS utility panels that feel like part of WeChat rather than a separate web-style product. The signature is a quiet translucent background with clearly bounded task groups; visual material is presentation only and remains independent from feature behavior such as sidebar entry hiding or ordering.

## 2. Color

AppKit colors use calibrated white values so the panel follows the current Aqua or Dark Aqua appearance.

| Role | Token | Light | Dark | Usage |
|---|---|---:|---:|---|
| Window | `YMWindowSurface` | white 0.96 / alpha 0.98 | white 0.08 / alpha 0.96 | Panel chrome |
| Content | `YMContentSurface` | white 0.94 / alpha 0.98 | white 0.06 / alpha 0.96 | Root content |
| Card | `YMCardSurface` | white 1.00 / alpha 0.82 | white 0.12 / alpha 0.78 | Settings groups |
| Card border | `YMCardBorder` | black / alpha 0.08 | white / alpha 0.10 | One-point card outline |
| Title text | `YMTextTitle` | white 0.08 | white 0.98 | Panel title |
| Primary text | `YMTextPrimary` | white 0.16 | white 0.92 | Row title and controls |
| Value text | `YMTextValue` | white 0.24 | white 0.86 | Current values and status |
| Subtitle text | `YMTextSubtitle` | white 0.46 | white 0.72 | Introductory copy |
| Secondary text | `YMTextSecondary` | white 0.52 | white 0.62 | Explanations and notes |

Accent, focus, warning, and error colors use AppKit semantic colors so system contrast and accessibility settings remain authoritative.

## 3. Typography

| Level | Size | Weight | Usage |
|---|---:|---|---|
| Panel title | 22 pt | Semibold | Window-level heading |
| Row title | 14 pt | Medium | Toggle labels |
| Section label | 13 pt | Medium | Compact group headings |
| Subtitle | 12 pt | Regular | Panel description and status |
| Secondary note | 11 pt | Regular | Footer and compatibility notes |

Use `NSFont systemFontOfSize:weight:` throughout. Chinese copy uses the system CJK font and natural AppKit metrics; custom typefaces are not introduced.

## 4. Spacing & Layout

All intentional spacing follows a 4 pt base unit. Utility panels use 24 pt outer card margins, 24-32 pt title margins, 12-16 pt row spacing, and 8 pt compact gaps. Controls align to a shared edge. A footer action bar separates status from the right-aligned Cancel and Save buttons. The sidebar manager opens at 620 x 640 pt with a 580 x 560 pt minimum; its grouped content owns scrolling only when the available height or accessibility text metrics cannot show every row without clipping.

## 5. Components

### Settings Panel

- **Structure**: titled `NSPanel`, root content view, full-size `NSVisualEffectView`, heading block, one or more cards, and a footer action bar. Sidebar management uses two ordered group cards.
- **Variants**: Aqua and Dark Aqua.
- **Spacing**: 24 pt card margin, 32 pt heading margin, 8-16 pt internal rhythm.
- **States**: hidden, visible/key, inactive appearance, clean draft, dirty draft, unsupported-status message.
- **Accessibility**: native tab order, system focus rings, concise Chinese labels.
- **Motion**: native AppKit panel presentation only; no decorative animation.
- **Layout**: compact desktop utility panel centered on first presentation; sidebar management may resize down to its declared minimum and scrolls only the grouped content, never the action bar.

### Settings Card

- **Structure**: layer-backed `NSView` containing related controls.
- **Variants**: light and dark surfaces.
- **Spacing**: 24 pt internal padding and 16 pt row rhythm.
- **States**: normal and appearance-changed.
- **Accessibility**: border and tonal shift both remain visible with increased contrast.
- **Motion**: none.
- **Layout**: vertical stack.

### Entry Toggle Row

- **Structure**: a native table row with checkbox, concise title, stable position, selection state, and row-level accessibility identifier. Per-entry descriptions are omitted when they merely restate the title.
- **Variants**: enabled preference, disabled preference, unavailable runtime.
- **Spacing**: 36 pt row height on the 4 pt grid with checkbox and title on a shared baseline.
- **States**: on, off, selected, focused, pressed, drag source, valid drop target, and unavailable runtime.
- **Accessibility**: the checkbox title names the entry; the row exposes its group and 1-based position; selection and enabled state are independent; keyboard operation remains native.
- **Motion**: native AppKit control state transition only.
- **Layout**: ordered vertical table within its native group card.

### Entry Group Card

- **Structure**: section label, `NSTableView` with no decorative header, and a compact trailing action strip containing `上移` and `下移`.
- **Variants**: `主要入口` for `聊天 / 通讯录 / 收藏`; `发现与服务` for `朋友圈 / 视频号 / 搜一搜 / 游戏中心（小游戏） / 小程序`.
- **Spacing**: 16 pt card padding, 8 pt heading-to-table gap, and 8 pt table-to-actions gap.
- **States**: no selection, selected row, dirty order, invalid cross-group drop, first-row boundary, and last-row boundary.
- **Accessibility**: each table has a concise Chinese label; Up/Down buttons include the selected entry in their help text; disabled boundary controls remain discoverable through their labels.
- **Motion**: native row insertion/reordering feedback only; reduced-motion behavior is equivalent and immediate.
- **Layout**: rows never move across group boundaries. Hidden rows stay present and sortable.

### Reorder Controls

- **Structure**: native drag-and-drop inside each table plus explicit text buttons `上移` and `下移` for keyboard and motor-accessible parity.
- **States**: enabled for a valid selected-row move; disabled at the matching boundary or with no selection; rejected cross-group drops leave the draft byte-for-byte unchanged.
- **Accessibility**: after a move, focus and selection remain on the same entry and VoiceOver receives the new 1-based position.
- **Motion**: no decorative animation; the row's changed position is the feedback.

### Panel Action Bar

- **Structure**: status label on the left, native Cancel and Save buttons on the right.
- **Variants**: connected runtime, waiting runtime, unsupported build, clean draft, and dirty draft.
- **States**: Save disabled while the draft matches persisted settings or is invalid; Save enabled after a valid change; Return activates Save and Escape activates Cancel. Status distinguishes visibility-only changes, order changes that require restart, connected/waiting runtime, and validation errors without relying on color alone.
- **Accessibility**: native buttons, focus rings, key equivalents, and concise labels.
- **Motion**: native AppKit button feedback only.
- **Layout**: fixed footer below the settings card; actions never overlap status text.

## 6. Motion & Interaction

Checkbox and reorder changes update an in-window draft only. Save validates all managed entries and persists one authoritative configuration. Visibility applies to the current sidebar; order applies to a newly constructed sidebar owner and therefore shows a concise restart-required status when the current owner still uses the prior order. Cancel, Escape, and the window close control discard the draft. Return activates Save only when the draft is valid and dirty. Dragging and Up/Down produce the same order. Do not add decorative motion. Window presentation, focus, checkbox feedback, row movement, and error alerts use native AppKit behavior and respect system reduced-motion settings.

## 7. Depth & Surface

Use a mixed native strategy: `NSVisualEffectMaterialUnderWindowBackground` for the panel atmosphere plus a one-point translucent border and tonal shift for cards. Cards use an 18 pt corner radius. Do not add custom drop shadows or colored glow to settings management surfaces.

## 8. Accessibility Constraints & Accepted Debt

### Constraints

- Follow the current Aqua/Dark Aqua appearance and AppKit semantic focus behavior.
- Keep primary text at least 14 pt and supporting text at least 11 pt in the existing compact utility convention.
- Ensure every entry is keyboard-toggleable and retains a visible focus ring.
- Ensure every reorder operation has both drag and keyboard/button paths, and keeps selection on the moved entry.
- Prevent disabling the final enabled primary entry and explain the constraint in plain Chinese.
- Avoid CJK truncation, single-character orphan lines, and clipped baselines.
- Do not expose the removed `聊天文件` label or a cross-group drop target in the accessibility tree.

### Accepted Debt

None for the sidebar manager. The panel is a macOS-only utility, so browser and mobile breakpoints do not apply.
