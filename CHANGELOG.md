# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Selection order index badges now appear on the right side of sidebar window items when two or more windows are selected

### Changed

- Window list in the sidebar is now pre-cached in the background via workspace event listeners (app activation, launch, termination), so it appears instantly when the overlay opens
- Improved highlight behavior for app-grouped sidebar items: the app header is now only shown as selected when all its windows are selected, and hovering over an app header highlights both the header and all its child windows

### Fixed

- Fixed the overlay not opening when the frontmost application has no windows; the overlay now opens with a "No windows" message and drag is disabled
- Fixed Finder's desktop being treated as a resizable window; when the desktop is focused, Tiley now targets Finder's frontmost real window instead, or shows "No windows" if none exist
- Fixed the overlay not opening when the frontmost application has no windows (e.g. Finder with no open windows, menu bar-only apps); now falls back to the topmost visible window on screen
- Fixed window position not being applied correctly on non-primary displays for some apps (e.g. Notion); added post-resize position verification with retry loop to handle apps that asynchronously revert position after a size change

## [4.1.1] - 2026-03-31

### Changed

- Default shortcut for selecting the next window changed from Tab to Space; previous window changed from Shift+Tab to Shift+Space
- Displaced windows now always animate back to their original positions when the overlay is dismissed

## [4.1.0] - 2026-03-31

### Added

- Modifier-held window cycling (Cmd+Tab-like interaction): hold the toggle modifier keys after opening the overlay, then press the trigger key repeatedly to cycle through windows; release the modifiers to bring the selected window to front; press a layout local shortcut key while holding modifiers to apply that layout
- Third-party license acknowledgements section in Settings (Sparkle, TelemetryDeck)

### Changed

- Settings and Permissions panels are now separate windows at normal (non-floating) level, so Sparkle update dialogs and other OS windows can appear above them
- Sidebar is now always visible; the sidebar show/hide toggle button has been removed
- Settings button moved from the footer bar to the left edge of the sidebar action bar
- Mini screen preview now always has rounded corners on all four sides, regardless of display type
- Miniature window title bar now shows the application name alongside the window title
- "Update available" badge replaced with a red dot on the settings button and a tooltip; the settings panel shows a popover on the "Check for Updates" button instead

## [4.0.9] - 2026-03-30

### Fixed

- Window resize failing and position getting displaced for certain apps: the fallback bounce position used when the initial resize is silently rejected was at the bottom of the screen (no room to expand), causing the window to get stuck at an incorrect position; now bounces to the top of the visible area and explicitly restores position if the resize still fails
- Displaced windows sometimes not restored to their original positions after selecting a background window: restoration relied on looking up windows in a list that could become stale; now stores window references directly in the displacement tracking data, and defers cleanup until the restoration animation completes
- "Add Shortcut" / "Add Global Shortcut" buttons only responded to clicks near the center; moved padding and background inside the button label so the entire visible area is clickable

## [4.0.8] - 2026-03-30

### Fixed

- Permissions panel window is no longer floating above other apps and OS dialogs while requesting accessibility access
- Wallpaper preview not displayed on macOS Tahoe 26.4: adapted to wallpaper Store plist structure change (`Desktop` → `Linked` key), added support for Photos wallpapers via wallpaper agent BMP cache, added `FillScreen` placement value (Tahoe's replacement for `Stretch`), and enabled display mode settings for non-system wallpaper providers
- Center and tile wallpaper display modes rendered images too small when the image had non-72 DPI metadata (e.g. Retina screenshots at 144 DPI); now always uses actual pixel dimensions

## [4.0.7] - 2026-03-29

### Fixed

- Tiled wallpaper display mode was not reflected in the mini-screen preview (the placement value "Tiled" from the macOS wallpaper Store plist was not matched correctly)
- Added debug logging for wallpaper resolution pipeline to help diagnose wallpaper display issues

## [4.0.6] - 2026-03-29

### Added

- Hovering over a multi-layout preset now shows layout index numbers on the mini-screen grid, full-size preview rectangles, and sidebar window list items, making it easy to see which layout applies to which window regardless of color vision

### Changed

- Fine-tuned the settings window UI to match macOS Tahoe look and feel: toolbar and action bar buttons now use capsule shape with system-adaptive hover/press fills, settings section cards use a subtle gray background without borders, toggles are sized to match System Settings, and shortcut rows are restructured with a dedicated "Display Move Shortcuts" section

### Fixed

- Sidebar windows beyond the preset layout count now correctly show the last layout's color instead of the primary selection color

## [4.0.5] - 2026-03-29

### Fixed

- Windows displaced to show a selected target now correctly restore to their original positions even when the user cycles through targets rapidly
- Single-window resize preview was too faint compared to multi-window layout previews; now uses the same opacity

## [4.0.4] - 2026-03-29

### Added

- Mini-screen layout preview shows window title bars (app icon, app name, window title) when hovering over any preset

### Changed

- Full-size layout preview title bar now shows app name alongside window title (format: "App Name — Window Title")

## [4.0.3] - 2026-03-29

### Added

- Multi-layout presets now resize multiple windows even with a single window selected — windows are picked by actual z-order (frontmost first)
- When selected windows are fewer than preset layout definitions, the selected window is always treated as primary and remaining slots are filled from z-order
- Sidebar window rows highlight with layout colors (blue, green, orange, purple) when hovering over a multi-layout preset

## [4.0.2] - 2026-03-29

### Changed

- Real-size layout preview now only shows previews for the number of selections defined in the preset (extra selected windows beyond the preset's selection count are no longer previewed)

## [4.0.1] - 2026-03-29

### Changed

- Selection color palette now cycles as blue, green, orange, purple (4 colors) so the 5th selection matches the 1st
- Default presets (Left/Right/Top/Bottom Half) now include a secondary selection for the opposite half

## [4.0.0] - 2026-03-29

### Added

- Multi-selection layout presets: define multiple grid regions per preset for arranging different windows in different positions
  - Each drag in the preset editor appends a new selection (1st, 2nd, 3rd, ...)
  - Selections show their index number and a delete button for easy management
  - Overlapping selections are prevented with visual feedback
  - When applying a multi-selection preset, windows are assigned by selection order: the initially selected window gets selection 1, the next selected window gets selection 2, etc.
  - Preset thumbnails and real-size previews display all selections with distinct indexed colors
  - Grid selections have a 1pt margin from physical screen edges for better visibility

### Changed

- Multi-window ordering now follows selection order instead of sidebar Z-order
  - The initially selected window is always primary; subsequently Cmd+clicked windows are appended in order
  - Shift+click range selections keep the anchor window as primary
  - Affects layout preset application, Bring to Front (Enter), and preview display

## [3.4.0] - 2026-03-28

### Added

- Multi-window selection in the sidebar: select multiple windows and perform batch actions on all of them
  - Click an application header to select all windows of that app
  - Cmd+click to toggle individual windows in/out of the selection
  - Shift+click to select a contiguous range of windows in sidebar order
- Batch actions for multi-selection: Bring to Front (preserving sidebar Z-order), resize/move to grid, move to display, and close/quit
- When closing multiple selected windows, apps whose windows are all selected will be quit (except Finder)

### Changed

- Clicking an application header in the sidebar now selects all windows of that app (previously selected only the frontmost)
- Selecting a window under an app group now keeps the application header highlighted
- Added a "Quit App" button next to the "Close Window" button for non-Finder apps with multiple windows in the sidebar action bar
- The "Close Window" tooltip now shows the window name (e.g., Close "Document")

## [3.3.2] - 2026-03-28

### Added

- Shortcuts for "Select Next Window", "Select Previous Window", "Bring to Front", and "Close / Quit" are now configurable in the Shortcuts settings
- Added "Close other windows of [App]" context menu item when right-clicking a window in the sidebar (shown only when the app has multiple windows)

### Changed

- Reorganized the Shortcuts settings section: window action shortcuts and display movement shortcuts are now grouped separately, each in their own card
- Display movement shortcuts are now global-only; removed local shortcut support and settings for display movement actions
- Updated toolbar buttons, quit button, action bar buttons, and dropdown menu button to use Liquid Glass interactive effect on macOS 26 (Tahoe), following the Human Interface Guidelines
- Window background now uses the system window background color for better compatibility with macOS appearance changes
- Displaced windows now animate back to their original positions when confirming a selection, applying a layout, or canceling with Escape

## [3.3.1] - 2026-03-28

### Added

- When selecting a window in the sidebar, overlapping windows are smoothly animated downward to reveal the selected window without changing focus
- A highlight border is shown around the currently selected window in the sidebar

### Fixed

- Fixed Tab/arrow key cycling order to match the sidebar display order (grouped by space, screen, and application)
- Displaced windows are restored to their original positions when the selection is canceled (Esc) or Tiley is closed

## [3.3.0] - 2026-03-27

### Fixed

- Preventive fix for excessive CPU usage that could occur in multi-display environments
- Fixed a status bar icon redraw loop that could cause 100% CPU usage when a badge overlay (update notification or debug indicator) was displayed
- Made Tiley windows always float above normal windows so they are not hidden behind target windows during Tab cycling

## [3.2.9] - 2026-03-27

### Fixed

- Fixed Tab/arrow key cycling order to match the sidebar display order (grouped by space, screen, and application)

## [3.2.8] - 2026-03-26

### Fixed

- Fixed Tab/arrow key window cycling in the sidebar alternating between only two windows instead of cycling through all windows

## [3.2.7] - 2026-03-26

### Fixed

- Fixed a crash that occurred when the app was launched as a login item (incomplete fix in 3.2.6)

## [3.2.6] - 2026-03-26

### Fixed

- Fixed a crash that occurred when the app was launched as a login item

## [3.2.5] - 2026-03-26

### Changed

- Unified the Shortcuts and Global Shortcut sections into a single Shortcuts section
- Unified shortcut setting UI across all shortcut types

### Fixed

- Fixed an issue where the main window could remain visible when the app went to the background
- Fixed display highlight border being clipped by rounded corners and notch on built-in displays by drawing the border below the menu bar area

## [3.2.4] - 2026-03-26

### Added

- Added display movement shortcuts to move windows between displays (primary, next, previous, pick from menu, or specific display)

## [3.2.3] - 2026-03-25

### Added

- Added directional arrow indicators to the "Move to Display" button and menu items, visually showing the direction of the target display based on the physical screen arrangement
- When the selected window is on another display, the grid overlay now shows a directional arrow and display arrangement icon in the center, guiding users to where their window is

### Changed

- Adjusted appearance when an update is available

## [3.2.2] - 2026-03-25

### Added

- Selecting a window in the sidebar temporarily brings it to the front for easier identification; the original window order is restored when switching to another window or cancelling
- Resize preview now displays a title bar with the app icon and window title, making it easier to identify which window is being arranged

## [3.2.1] - 2026-03-25

### Fixed

- Fixed sidebar showing no windows in multi-screen environments due to space filtering only considering a single display's active space

## [3.2.0] - 2026-03-25

### Added

- When multiple Mission Control spaces exist, the sidebar shows only windows on the current space
- Grid overlay now shows a miniature window preview with traffic light buttons, app icon, and window title at the target window's current position

### Changed

- Overlay dismissal is now more responsive when applying layouts or bringing windows to front
- Windows in native macOS fullscreen mode are now automatically exited from fullscreen before resizing

## [3.1.1] - 2026-03-24

### Fixed

- Fixed system wallpaper thumbnails incorrectly rendering as tiled instead of fill
- Fixed wrong wallpaper shown for dynamic wallpapers; added thumbnail support for Sequoia, Sonoma, Ventura, Monterey, and Macintosh provider-based wallpapers
- Menu bar text in the grid preview now adapts to wallpaper brightness (black on light wallpapers, white on dark) matching macOS behavior

## [3.1.0] - 2026-03-24

### Changed

- Replaced hover-reveal kebab (more) menus in the window list sidebar with native right-click context menus for a more macOS-native experience
- Added action buttons (Move to Screen, Close/Quit, Hide Others) next to the sidebar search field for quick access to common window operations
- Layout preset grid thumbnails now match the aspect ratio of the screen's usable area (excluding menu bar and Dock), reflecting portrait or landscape orientation per screen

### Removed

- Removed hover-reveal kebab menu buttons and hover close buttons from sidebar rows (replaced by context menus and action bar)

### Fixed

- Fixed window resizing sometimes failing when moving a window from one screen to another (especially to a taller portrait monitor) by adding a retry mechanism for cross-screen moves

## [3.0.1] - 2026-03-23

### Added

- When bringing a window to front via Enter or double-click, the window is now moved to the screen where the mouse pointer is located if it differs from the window's current screen. The window is repositioned to fit within the destination screen, resizing only if necessary.

### Changed

- Improved overlay display performance by ~80% through controller pooling/reuse, deferred window list loading, and prioritized target screen rendering
- Renamed internal debug log setting from `useAppleScriptResize` to `enableDebugLog` to better reflect its purpose

### Fixed

- Fixed window resize silently failing on the primary screen for some apps (e.g. Chrome) by adding size verification and bounce retry, matching the existing workaround used for secondary screens
- Fixed clicking the menu bar icon while the overlay is visible now dismisses the overlay (same as pressing ESC), instead of opening the main window

## [3.0.0] - 2026-03-23

### Added

- Integrated TelemetryDeck analytics SDK for privacy-friendly usage tracking (overlay opened, layout applied, preset applied, settings changed)
- Sidebar windows are now grouped by screen and by application; multi-window apps show an app header with indented window rows
- Screen header rows in the sidebar now have a kebab menu with "Gather windows" and "Move windows to" actions for managing windows across screens
- App header kebab menu with "Move all windows to screen", "Hide others", and "Quit" actions
- Single-window app kebab menu with "Move to screen", "Hide others", and "Quit" actions
- Empty screens (with no windows) are now shown in the sidebar with their screen header

### Changed

- Grid background now accurately reflects the macOS wallpaper display settings (fill, fit, stretch, center, and tile modes), including correct tile scaling, physical pixel ratio for center mode, and fill color for letterbox areas
- Layout grid preview now shows the full screen frame including the menu bar, Dock, and notch, giving a more accurate representation of the actual display

### Fixed

- Fixed window position not being applied when the window is already at the target position before resize; AX de-duplication now defeated via pre-nudge
- Reduced visible flicker when resizing on non-primary screens; resize is now attempted in-place first, and the primary-screen bounce only occurs when the in-place resize has no effect at all
- When bouncing to the primary screen for resize, the window is now placed at the bottom edge (mostly off-screen) instead of at the origin, minimizing visible flicker

## [2.2.0] - 2026-03-21

### Changed

- Grid tiles are now transparent when not selected
- Grid aspect ratio now matches the screen's visible area (excluding menu bar and Dock); if the grid would be too tall, its width is reduced proportionally to ensure at least 4 presets remain visible
- Desktop picture is now displayed as the background of the layout grid (with transparency and rounded corners)
- Drag-selected cells are now semi-transparent, showing the desktop picture beneath
- Preset hover highlight in the grid now uses the same style as the drag selection

### Added

- Window list sidebar is now displayed on all screens in multi-monitor setups, not just the target screen
- Sidebar state (visibility, selected item, search text) is synchronized across all screen windows
- Optional resize debug log (`~/tiley.log`) for diagnosing window placement issues (Settings > Debug)

### Fixed

- Fixed window placement using stale screen geometry when the Dock or menu bar auto-shows/hides while the overlay is open
- Fixed window resize failing on non-primary screens in mixed-DPI setups; the window is now temporarily moved to the primary display for resizing, then placed at the target position
- Fixed position not being applied after resize when some apps silently revert position changes (AX de-duplication workaround via 1px nudge)
- When an app's minimum window size prevents the requested size, the window position is now recalculated so it stays within the visible screen area instead of extending beyond the edge
- Eliminated visible window flicker when switching target windows across screens; windows are no longer recreated on screen change

## [2.1.0] - 2026-03-20

### Added

- Double-click a window in the sidebar list to bring it to the foreground and dismiss the layout grid
- Context menu (ellipsis button) on sidebar window rows with three actions:
  - "Close other windows of [App]" — closes other windows of the same app (shown only when the app has multiple windows)
  - "Quit [App]" — terminates the application
  - "Hide windows besides [App]" — hides all other applications (Cmd-H equivalent), unhides the selected app if it was hidden
- Hidden (Cmd-H) applications now appear in the sidebar as placeholder entries (app name only) and are displayed at 50% opacity
- Selecting a hidden app (Enter, double-click, grid/layout resize) automatically unhides it and operates on its frontmost window

## [2.0.3] - 2026-03-19

### Added

- Sparkle gentle scheduled update reminders: when a background update check finds a new version, a red badge dot appears on the menu bar icon and "Update available" labels appear next to the gear button and the "Check for Updates" button in settings
- If the menu bar icon is hidden when an update is detected, it is temporarily shown with the badge and hidden again after the update session ends

### Changed

- Settings window is now hidden when Sparkle finds an update (previously only when download started), and restored when the user cancels
- Settings window title is now localized across all supported languages
- Version number moved from the settings title to the Updates section, displayed next to the "Check for Updates" button

## [2.0.2] - 2026-03-19

### Added

- Close button on window list sidebar rows: hover over a window name to reveal an × button that closes the window
- "Quit app when closing last window" setting (Settings > Windows): when enabled (default), closing an app's last window terminates the app; when disabled, only the window is closed
- Close button tooltip shows the window name, or the app name when it will quit the app
- "/" keyboard shortcut to close the selected window (or quit the app if it's the last window and the setting is enabled)

## [2.0.1] - 2026-03-19

### Changed

- Redesigned the settings panel with a Tahoe-style layout: glass-backed sections (Liquid Glass on macOS 26+), compact toolbar header with back/quit buttons, and iOS-like grouped rows with inline controls

## [2.0.0] - 2026-03-19

### Changed

- Replaced the window target dropdown menu with a sidebar panel using Liquid Glass (macOS Tahoe); includes a search field with full IME support, arrow-key and Tab/Shift+Tab navigation, and Cmd+F to toggle visibility

### Improved

- Windows in the sidebar are listed in z-order (front-to-back) rather than grouped by application
- Filtered out non-standard windows (palettes, toolbars, etc.) from the window target list so only resizable document windows are shown

## [1.2.7] - 2026-03-18

### Improved

- Automatically close the main window when Sparkle begins downloading an update

### Fixed

- Eliminated visible seams in the resize constraint preview overlay when both horizontal and vertical overflow (red) or underflow (yellow) regions are displayed simultaneously

## [1.2.6] - 2026-03-18

### Fixed

- When resizing a background window of the same application via Tab cycling, the window is now brought to the front if it would be hidden behind other windows of that application

## [1.2.5] - 2026-03-18

### Added

- Window resize constraint detection: automatically detects per-axis resizability using a fast 3-tier check (non-resizable → full-screen button → 1px probe fallback)
- Layout preview overlay now shows red regions where the window cannot expand and yellow regions where the window cannot shrink, giving visual feedback on resize constraints before applying

## [1.2.4] - 2026-03-17

### Improved

- Refined layout preset editing UI: delete button moved next to the confirm button, edit/action buttons placed in a dedicated column to avoid overlapping shortcuts
- Layout grid selection is now editable in edit mode: drag on the grid to update the preset's position with live preview and highlight

## [1.2.3] - 2026-03-17

### Improved

- Fine-tuned layout preset editing UI: delete button now overlays the grid preview with a confirmation dialog, opaque hover background, and consistent button styling

## [1.2.2] - 2026-03-17

### Changed

- Redesigned layout preset editing for a more intuitive settings experience

## [1.2.1] - 2026-03-17

### Fixed

- Fix "Move to Applications" dialog incorrectly shown instead of "Copy" when launching from a downloaded DMG (Gatekeeper App Translocation caused the disk image path to be unrecognized)

## [1.2.0] - 2026-03-17

### Added

- Window target switching: press Tab / Shift+Tab while the overlay is showing to cycle through available windows
- Window target dropdown: click the target info area to select a window from a popup menu
- Tab and Shift+Tab are now reserved and cannot be assigned as layout shortcuts

## [1.1.8] - 2026-03-16

### Added

- After copying from a DMG, offer to eject the disk image and move the DMG file to Trash
- Detect a mounted Tiley DMG on launch from /Applications (e.g. after manual Finder copy) and offer to eject and trash it

## [1.1.7] - 2026-03-16

### Changed

- Switch distribution format from zip to DMG with Applications shortcut and custom Finder layout (large icons, square window)

### Fixed

- Fix "Move to Applications" failing with a read-only volume error when the app is launched from a downloaded zip without moving it first (Gatekeeper App Translocation)
- Show "Copy to Applications" dialog instead of "Move" when the app is launched from a disk image (DMG)

## [1.1.6] - 2026-03-16

### Fixed

- Fix settings window requiring two activations to open on multi-screen setups (menu bar icon, Cmd+,, and Tiley menu → Settings all affected)

## [1.1.5] - 2026-03-16

### Added

- Multi-screen overlay: the layout grid window now appears on every connected screen simultaneously
- Cross-screen tiling: drag grid or click a preset on a secondary screen to tile the target window to that screen
- Preview overlay appears on the screen where the hovered preset window is displayed

### Fixed

- Fix maximize layout not filling the full screen when tiling across displays of different sizes
- Fix local keyboard shortcuts (arrow keys, preset hotkeys) not working after the second overlay activation
- Fix only some overlay windows closing when clicking a background app window; all overlay windows now dismiss together
- Fix preset hover/selection highlight appearing on all screens; it now only appears on the screen where the mouse cursor resides

## [1.1.4] - 2026-03-15

### Fixed

- Fix "Show Dock icon" toggle not working: Dock icon was not appearing when enabled, and toggling off caused the window to disappear
- Prevent app from terminating unexpectedly when all windows are closed
- Fix window target defaulting to Tiley itself when launched by double-clicking the app; now correctly targets the previously active app's window
- Fix main window appearing on login-item launch: the window no longer opens when the app is auto-launched as a login item at system startup

## [1.1.3] - 2026-03-15

### Fixed

- Fix grid preview overlay sometimes staying visible on screen, causing duplicate overlays to stack up

## [1.1.2] - 2026-03-15

### Added

- Localization: Spanish, German, French, Portuguese (Brazil), Russian, Italian

## [1.1.1] - 2026-03-15

## [1.1.0] - 2026-03-15

### Added

- Dark mode support: all UI elements automatically adapt to the system appearance setting

### Changed

- Shortcut display now uses symbols (⌃ ⌥ ⇧ ⌘ ← → ↑ ↓) instead of English key names for modifier and arrow keys

### Fixed

- Main window now hides automatically when Sparkle shows the update dialog, preventing it from being obscured

## [1.0.1] - 2026-03-15

### Fixed

- Add missing localization for shortcut add button tooltips ("Add Shortcut" / "Add Global Shortcut")

## [1.0.0] - 2026-03-14

### Added

- Prompt to move the app to /Applications when launched from another location
- Per-shortcut global flag: each shortcut within a layout preset can now individually be set as global or local
- Separate add buttons for regular shortcuts and global shortcuts, with instant popover tooltips

### Changed

- Global shortcut setting moved from per-preset to per-shortcut granularity
- Existing presets with the legacy per-preset global flag are automatically migrated

## [0.9.0] - 2026-03-14


- Initial release

### Added

- Grid overlay for window tiling with customizable grid size
- Global keyboard shortcut (Shift + Command + Space) to activate overlay
- Drag across grid cells to define target window region
- Layout presets for saving and restoring window arrangements
- Multi-display support
- Launch at login option
- Localization: English, Japanese, Korean, Simplified Chinese, Traditional Chinese


[Unreleased]: https://github.com/yusuke/tiley/compare/v4.1.1...HEAD
[4.1.1]: https://github.com/yusuke/tiley/releases/tag/v4.1.1
[4.1.0]: https://github.com/yusuke/tiley/releases/tag/v4.1.0
[4.0.9]: https://github.com/yusuke/tiley/releases/tag/v4.0.9
[4.0.8]: https://github.com/yusuke/tiley/releases/tag/v4.0.8
[4.0.7]: https://github.com/yusuke/tiley/releases/tag/v4.0.7
[4.0.6]: https://github.com/yusuke/tiley/releases/tag/v4.0.6
[4.0.5]: https://github.com/yusuke/tiley/releases/tag/v4.0.5
[4.0.4]: https://github.com/yusuke/tiley/releases/tag/v4.0.4
[4.0.3]: https://github.com/yusuke/tiley/releases/tag/v4.0.3
[4.0.2]: https://github.com/yusuke/tiley/releases/tag/v4.0.2
[4.0.1]: https://github.com/yusuke/tiley/releases/tag/v4.0.1
[4.0.0]: https://github.com/yusuke/tiley/releases/tag/v4.0.0
[3.4.0]: https://github.com/yusuke/tiley/releases/tag/v3.4.0
[3.3.2]: https://github.com/yusuke/tiley/releases/tag/v3.3.2
[3.3.1]: https://github.com/yusuke/tiley/releases/tag/v3.3.1
[3.3.0]: https://github.com/yusuke/tiley/releases/tag/v3.3.0
[3.2.9]: https://github.com/yusuke/tiley/releases/tag/v3.2.9
[3.2.8]: https://github.com/yusuke/tiley/releases/tag/v3.2.8
[3.2.7]: https://github.com/yusuke/tiley/releases/tag/v3.2.7
[3.2.6]: https://github.com/yusuke/tiley/releases/tag/v3.2.6
[3.2.5]: https://github.com/yusuke/tiley/releases/tag/v3.2.5
[3.2.4]: https://github.com/yusuke/tiley/releases/tag/v3.2.4
[3.2.3]: https://github.com/yusuke/tiley/releases/tag/v3.2.3
[3.2.2]: https://github.com/yusuke/tiley/releases/tag/v3.2.2
[3.2.1]: https://github.com/yusuke/tiley/releases/tag/v3.2.1
[3.2.0]: https://github.com/yusuke/tiley/releases/tag/v3.2.0
[3.1.1]: https://github.com/yusuke/tiley/releases/tag/v3.1.1
[3.1.0]: https://github.com/yusuke/tiley/releases/tag/v3.1.0
[3.0.1]: https://github.com/yusuke/tiley/releases/tag/v3.0.1
[3.0.0]: https://github.com/yusuke/tiley/releases/tag/v3.0.0
[2.2.0]: https://github.com/yusuke/tiley/releases/tag/v2.2.0
[2.1.0]: https://github.com/yusuke/tiley/releases/tag/v2.1.0
[2.0.3]: https://github.com/yusuke/tiley/releases/tag/v2.0.3
[2.0.2]: https://github.com/yusuke/tiley/releases/tag/v2.0.2
[2.0.1]: https://github.com/yusuke/tiley/releases/tag/v2.0.1
[2.0.0]: https://github.com/yusuke/tiley/releases/tag/v2.0.0
[1.2.7]: https://github.com/yusuke/tiley/releases/tag/v1.2.7
[1.2.6]: https://github.com/yusuke/tiley/releases/tag/v1.2.6
[1.2.5]: https://github.com/yusuke/tiley/releases/tag/v1.2.5
[1.2.4]: https://github.com/yusuke/tiley/releases/tag/v1.2.4
[1.2.3]: https://github.com/yusuke/tiley/releases/tag/v1.2.3
[1.2.2]: https://github.com/yusuke/tiley/releases/tag/v1.2.2
[1.2.1]: https://github.com/yusuke/tiley/releases/tag/v1.2.1
[1.2.0]: https://github.com/yusuke/tiley/releases/tag/v1.2.0
[1.1.8]: https://github.com/yusuke/tiley/releases/tag/v1.1.8
[1.1.7]: https://github.com/yusuke/tiley/releases/tag/v1.1.7
[1.1.6]: https://github.com/yusuke/tiley/releases/tag/v1.1.6
[1.1.5]: https://github.com/yusuke/tiley/releases/tag/v1.1.5
[1.1.4]: https://github.com/yusuke/tiley/releases/tag/v1.1.4
[1.1.3]: https://github.com/yusuke/tiley/releases/tag/v1.1.3
[1.1.2]: https://github.com/yusuke/tiley/releases/tag/v1.1.2
[1.1.1]: https://github.com/yusuke/tiley/releases/tag/v1.1.1
[1.1.0]: https://github.com/yusuke/tiley/releases/tag/v1.1.0
[1.0.1]: https://github.com/yusuke/tiley/releases/tag/v1.0.1
[1.0.0]: https://github.com/yusuke/tiley/releases/tag/v1.0.0
[0.9.0]: https://github.com/yusuke/tiley/releases/tag/v0.9.0
