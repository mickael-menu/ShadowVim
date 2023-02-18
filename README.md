<div align="center">
<h1>ShadowVim</h1>
<h4>Neovim <em>inside</em> Xcode, for real.</h4>

<img width="800" src="https://user-images.githubusercontent.com/58686775/219877113-367a0880-de31-46e3-b6a7-bf305077ec8c.gif"/>

<p>:warning: Experimental: Keep a backup of your files before editing them with ShadowVim</p>
</div>

## Description

ShadowVim gives the illusion of using Neovim inside Xcode by:

1. intercepting key events in Xcode's source editors
2. forwarding them to a background Neovim instance
3. applying the changes back to Xcode

### Highlights

* This not a Vim emulation, but real Neovim!
* Vim plugins (without UI) work out of the box. Hello [`vim-surround`](https://github.com/tpope/vim-surround), [`argtextobj.vim`](https://github.com/vim-scripts/argtextobj.vim) and whatnot.
* Add key mappings to trigger native Xcode features from Nvim (e.g. "Jump to Definition" on `gd`).

[See the changelog](CHANGELOG.md) for the list of upcoming features waiting to be released.

## Install

[Check out the latest release](https://github.com/mickael-menu/ShadowVim/releases) for pre-built binaries for macOS.

## Setup

### Xcode settings

The synchronization works best if you disable Xcode's auto-indentation and a couple of other settings. This can be done from the command line:

```sh
# First, create a backup of your current Xcode settings
defaults export -app Xcode ~/Downloads/Xcode.plist

# Then disable these settings.
defaults write -app Xcode DVTTextAutoCloseBlockComment -bool NO
defaults write -app Xcode DVTTextAutoInsertCloseBrace -bool NO
defaults write -app Xcode DVTTextEditorTrimTrailingWhitespace -bool NO
defaults write -app Xcode DVTTextEnableTypeOverCompletions -bool NO
defaults write -app Xcode DVTTextIndentCaseInC -bool NO
defaults write -app Xcode DVTTextUsesSyntaxAwareIndenting -bool NO
```

If you decide to remove ShadowVim, you can restore your previous settings with:

```sh
defaults import -app Xcode ~/Downloads/Xcode.plist
```

### Neovim configuration

:point_up: The default Nvim indent files for Swift are not great. It's highly recommended that you install [`keith/swift.vim`](https://github.com/keith/swift.vim) with your Nvim packages manager of choice.

Since many Vim plugins can cause issues with ShadowVim, it is recommended to start from an empty `init.vim`.

To determine if Neovim is running in Xcode, add to your `init.vim`:

```vim
if exists('g:shadowvim')
    " ShadowVim-specific statements
endif
```

Or to your `init.lua`:

```lua
if vim.g.shadowvim then
    -- ShadowVim-specific statements
end
```

To conditionally activate plugins, `vim-plug` has a
[few solutions](https://github.com/junegunn/vim-plug/wiki/tips#conditional-activation).

#### Adding keybindings

Only <kbd>⌃</kbd>/<kbd>C-</kbd>-based keyboard shortcuts can be customized in Neovim. <kbd>⌘</kbd>-based hotkeys are handled directly by Xcode.

The `SVPressKeys` user command triggers a keyboard shortcut in Xcode. This is convenient to bind Neovim commands to Xcode features, such as:

```viml
" Jump to Definition
nmap gd <Cmd>SVPressKeys C-D-J<CR>
```

:point_up: With Vim, <kbd>D-</kbd> stands for <kbd>⌘</kbd> and <kbd>M-</kbd> for <kbd>⌥</kbd>.

##### Navigation keybindings

Cross-buffers navigation is not yet supported with ShadowVim. Therefore, it is recommended to override the <kbd>C-o</kbd> and <kbd>C-i</kbd> mappings to use Xcode's navigation instead.

```viml
nmap <C-o> <Cmd>SVPressKeys C-D-Left<CR>
nmap <C-i> <Cmd>SVPressKeys C-D-Right<CR>
```

Unfortunately, this won't work in read-only source editors. As a workaround, you can rebind **Go back** to <kbd>⌃O</kbd> and **Go forward** to <kbd>⌃I</kbd> in Xcode's Key Bindings preferences, then in Neovim:

```viml
nmap <C-o> <Cmd>SVPressKeys C-o<CR>
nmap <C-i> <Cmd>SVPressKeys C-i<CR>
```

As `SVPressKeys` is not recursive, this is fine.

## Usage

### Menu bar icon

ShadowVim adds a new menu bar icon (🅽) with a couple of useful features which can also be triggered with global hotkeys:

* **Keys Passthrough** (<kbd>⌃⌥⌘.</kbd>) disables temporarily the Neovim synchronization. You **must** use this when renaming a symbol with Xcode's refactor tools, otherwise the buffer will get messed up.
* **Reset ShadowVim** (<kbd>⌃⌥⌘⎋</kbd>) kills Neovim and restarts the synchronization. This might be useful if you get stuck.

## Attributions

Thanks to [kindaVim](https://kindavim.app/) and [SketchyVim](https://github.com/FelixKratz/SketchyVim) for showing me this was possible.

* [Neovim](https://github.com/neovim/neovim), duh.
* [Sparkle](https://sparkle-project.org/) provides the auto-updater.
* [MessagePack.swift](https://github.com/a2/MessagePack.swift) is used to communicate with Nvim using MessagePack-RPC.
* [Sauce](https://github.com/Clipy/Sauce) helps supporting virtual keyboard layouts.
* [NSLogger](https://github.com/fpillet/NSLogger) for keeping me sane while debugging.
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates the project, because `.xcodeproj` is meh.

