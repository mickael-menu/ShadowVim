# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

* Xcode's settings are automatically updated to prevent conflicts when running ShadowVim.
    * The user is prompted with a bunch of terminal commands reverting the changes.

### Fixed

* Fix **Quit** and **Reset** buttons in the error dialogs.
* Fix synchronizing buffers with extra newlines at the end.
* Fix activating ShadowVim when restarting Xcode.
* Improve handling of some AX errors.

## [0.1]

### Added

* Basic Neovim / UI buffer and cursor synchronization.
* Support for **Normal**, **Insert** and **Replace** modes.
* Neovim user commands to trigger UI keyboard shortcuts.

[unreleased]: https://github.com/mickael-menu/ShadowVim/compare/main...HEAD
[0.2]: https://github.com/mickael-menu/ShadowVim/compare/0.1.0...0.2.0
[0.1]: https://github.com/mickael-menu/ShadowVim/tree/0.1.0
