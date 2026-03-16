# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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


[Unreleased]: https://github.com/yusuke/tiley/compare/v1.1.4...HEAD
[1.1.4]: https://github.com/yusuke/tiley/releases/tag/v1.1.4
[1.1.3]: https://github.com/yusuke/tiley/releases/tag/v1.1.3
[1.1.2]: https://github.com/yusuke/tiley/releases/tag/v1.1.2
[1.1.1]: https://github.com/yusuke/tiley/releases/tag/v1.1.1
[1.1.0]: https://github.com/yusuke/tiley/releases/tag/v1.1.0
[1.0.1]: https://github.com/yusuke/tiley/releases/tag/v1.0.1
[1.0.0]: https://github.com/yusuke/tiley/releases/tag/v1.0.0
[0.9.0]: https://github.com/yusuke/tiley/releases/tag/v0.9.0
