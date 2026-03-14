# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Dark mode support: all UI elements automatically adapt to the system appearance setting

### Changed

- Shortcut display now uses symbols (⌃ ⌥ ⇧ ⌘ ← → ↑ ↓) instead of English key names for modifier and arrow keys

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


[Unreleased]: https://github.com/yusuke/tiley/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/yusuke/tiley/releases/tag/v1.0.1
[1.0.0]: https://github.com/yusuke/tiley/releases/tag/v1.0.0
[0.9.0]: https://github.com/yusuke/tiley/releases/tag/v0.9.0
