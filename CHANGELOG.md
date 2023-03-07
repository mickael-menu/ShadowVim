# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

* Support for Visual and Select modes feedback.
    * Block-wise selection (<kbd>C-v</kbd>) is displayed as character-wise because of a limitation with the Xcode accessibility APIs.
* Use `SVPress` to trigger click events from Neovim bindings.
    ```viml
    " Show the Quick Help pop-up for the symbol at the caret location (<kbd>⌥ + Left Click</kbd>).
    nmap K <Cmd>SVPress <LT>M-LeftMouse><CR>

    " Perform a right click at the caret location.
    nmap gr <Cmd>SVPress <LT>RightMouse><CR>
    ```

### Changed

* `SVPressKeys` was renamed to `SVPress`.
* `SVPress` now emits the keyboard shortcut system-wide instead of only in the Xcode process.
    * This can be used to have a custom passthrough for hot keys (e.g. <kbd>⌥\`</kbd> to open iTerm) by adding this to your `init.vim`:
    ```viml
    if exists('g:shadowvim')
        map <A-`> <Cmd>SVPressKeys <LT>A-`><CR>
    endif
    ```
* The system paste shortcut (<kbd>⌘V</kbd>) is now overridden and handled by Neovim to improve performances and the undo history.


## [0.1.1]

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
[0.1.1]: https://github.com/mickael-menu/ShadowVim/compare/0.1.0...0.1.1
[0.1]: https://github.com/mickael-menu/ShadowVim/tree/0.1.0
