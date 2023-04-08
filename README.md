<div align="center">
<h1>ShadowVim</h1>
<h4>Neovim <em>inside</em> Xcode, for real.</h4>

<img width="800" src="https://user-images.githubusercontent.com/58686775/219877113-367a0880-de31-46e3-b6a7-bf305077ec8c.gif"/>
</div>

## Description

ShadowVim provides a Vim mode within Xcode powered by a background Neovim instance.

:warning: **Still experimental.** Keep a backup of your files before editing them with ShadowVim.

### Highlights

* This is not a Vim emulation, but real Neovim with macros, `.`, Ex commands, etc.
* Vim plugins (without UI) work out of the box. Hello [`vim-surround`](https://github.com/tpope/vim-surround), [`argtextobj.vim`](https://github.com/vim-scripts/argtextobj.vim) and whatnot.
* Add key mappings to trigger native Xcode features from Neovim (e.g. "Jump to Definition" on `gd`).

[See the changelog](CHANGELOG.md) for the list of upcoming features waiting to be released.

### How does it work?

ShadowVim uses macOS's Accessibility API to keep Xcode and Neovim synchronized. It works by:

1. intercepting key and focus events in Xcode
2. forwarding them to a background Neovim instance
3. applying the changes back to Xcode's source editors

## Install

[Check out the latest release](https://github.com/mickael-menu/ShadowVim/releases) for pre-built binaries for macOS.

### Minimum Requirements

| ShadowVim | macOS | Xcode | Neovim |
|------------|-------|-------|--------|
| latest     | 13.0  | 14    | 0.8    |

## Setup

### Neovim configuration

:point_up: The default Neovim indent files for Swift are not great. For a better alternative, install [`keith/swift.vim`](https://github.com/keith/swift.vim) with your Neovim package manager.

Since many Vim plugins can cause issues with ShadowVim, it is recommended to start from an empty `init.vim`.

To determine if Neovim is running in ShadowVim, add to your `init.vim`:

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

#### Adding key bindings

Only <kbd>⌃</kbd>/<kbd>C-</kbd>-based keyboard shortcuts can be customized in Neovim. <kbd>⌘</kbd>-based hotkeys are handled directly by Xcode.

The `SVPress` user command triggers a keyboard shortcut or mouse click in Xcode. This is convenient to bind Neovim commands to Xcode features, such as:

```viml
" Jump to Definition (⌃⌘J).
map gd <Cmd>SVPress <LT>C-D-j><CR>

" Find Selected Symbol in Workspace (⌃⇧⌘J).
map gr <Cmd>SVPress <LT>C-S-D-f><CR>

" Show the Quick Help pop-up for the symbol at the caret location (<kbd>⌥ + Left Click</kbd>).
map K <Cmd>SVPress <LT>M-LeftMouse><CR>
```

:warning: The first `<` needs to be escaped as `<LT>` when calling `SVPress` from a key binding.

| Modifier | macOS        | Nvim                           |
|----------|--------------|--------------------------------|
| control  | <kbd>⌃</kbd> | <kbd>C-</kbd>                  |
| option   | <kbd>⌥</kbd> | <kbd>M-</kbd> or <kbd>A-</kbd> |
| shift    | <kbd>⇧</kbd> | <kbd>S-</kbd>                  |
| command  | <kbd>⌘</kbd> | <kbd>D-</kbd>                  |

Take a look at the [Tips and tricks](#tips-and-tricks) section for a collection of useful bindings.

## Usage

### Menu bar icon

ShadowVim adds a new menu bar icon (🅽) with a couple of useful features which can also be triggered with global hotkeys:

* **Keys Passthrough** (<kbd>⌃⌥⌘.</kbd>) lets Xcode handle key events until you press <kbd>⎋</kbd>. You **must** use this when renaming a symbol with Xcode's refactor tools, otherwise the buffer will get messed up.
* **Reset ShadowVim** (<kbd>⌃⌥⌘⎋</kbd>) kills Neovim and resets the synchronization. This might be useful if you get stuck.

### Neovim user commands

The following commands are available in your bindings when Neovim is run by ShadowVim.

* `SVPress` triggers a keyboard shortcut or mouse click in Xcode. The syntax is the same as Neovim's key bindings, e.g. `SVPress <D-s>` to save the current file. Mouse clicks are performed at the current caret location.
* `SVEnableKeysPassthrough` switches on the Keys Passthrough mode, which lets Xcode handle key events until you press <kbd>⎋</kbd>.
* `SVReset` kills Neovim and resets the synchronization. This might be useful if you get stuck.
* `SVSynchronizeUI` requests Xcode to reset the current file to the state of the Neovim buffer. You should not need to call this manually.
* `SVSynchronizeNvim` requests Neovim to reset the current buffer to the state of the Xcode file. You should not need to call this manually.

## Tips and tricks

### Don't use `:w`

Neovim is in read-only mode, so `:w` won't do anything. Use the usual <kbd>⌘S</kbd> to save your files.

### Custom passthrough for hot keys

All keyboard shortcuts that are not using the <kbd>⌘</kbd> modifier are sent to Neovim. This means that if you have a global hot key (e.g. <kbd>⌥\`</kbd> to open iTerm), it won't work when Xcode is focused.

As a workaround, you can add a custom mapping to your `init.vim` to retrigger your hot key globally.

```viml
map <A-`> <Cmd>SVPress <LT>A-`><CR>
```

### Navigation with <kbd>C-o</kbd> and <kbd>C-i</kbd>

Cross-buffers navigation is not yet supported with ShadowVim. Therefore, it is recommended to override the <kbd>C-o</kbd> and <kbd>C-i</kbd> mappings to use Xcode's navigation instead.

```viml
map <C-o> <Cmd>SVPress <LT>C-D-Left><CR>
map <C-i> <Cmd>SVPress <LT>C-D-Right><CR>
```

Unfortunately, this won't work in read-only source editors. As a workaround, you can rebind **Go back** to <kbd>⌃O</kbd> and **Go forward** to <kbd>⌃I</kbd> in Xcode's **Key Bindings** preferences, then in Neovim:

```viml
map <C-o> <Cmd>SVPress <LT>C-o><CR>
map <C-i> <Cmd>SVPress <LT>C-i><CR>
```

As `SVPress` is not recursive, this will perform the native Xcode navigation.

### Triggering Xcode's completion

Xcode's completion generally works with ShadowVim. But there are some cases where the pop-up completion does not appear automatically.

As the default Xcode shortcut to trigger the completion (<kbd>⎋</kbd>) is already used in Neovim to go back to the normal mode, you might want to set a different one in Xcode's **Key Bindings** preferences. <kbd>⌘P</kbd> is a good candidate, who needs to print their code anyway?

### Completion placeholders

You cannot jump between placeholders in a completion snippet using <kbd>tab</kbd>, as it is handled by Neovim. As a workaround, you can use these custom Neovim key bindings to select or modify the next placeholder:

```viml
map gp /<LT>#.\{-}#><CR>gn
map cap /<LT>#.\{-}#><CR>cgn
```

### Mouse clicks

Here are some useful bindings simulating mouse clicks.

```viml
" Show the Quick Help pop-up for the symbol at the caret location (<kbd>⌥ + Left Click</kbd>).
map K <Cmd>SVPress <LT>M-LeftMouse><CR>

" Perform a right click at the caret location.
map gR <Cmd>SVPress <LT>RightMouse><CR>
```

### Window management

Use the following bindings to manage Xcode's source editor with the usual <kbd>C-w</kbd>-based keyboard shortcuts.

```viml
" Split vertically.
map <C-w>v <Cmd>SVPress <LT>C-D-t><CR>
" Split horizontally.
map <C-w>s <Cmd>SVPress <LT>C-M-D-t><CR>

" Close the focused editor.
" Note: Xcode 14 doesn't focus the previous one... As a workaround, ⌃C is triggered to focus the first one.
map <C-w>c <Cmd>SVPress <LT>C-S-D-w><CR><Cmd>SVPress <LT>C-`><CR>
" Close all other source editors.
map <C-w>o <Cmd>SVPress <LT>C-S-M-D-w><CR>

" Focus the editor on the left.
map <C-w>h <Cmd>SVPress <LT>D-j><CR><Cmd>SVPress h<CR><Cmd>SVPress <LT>CR><CR>
" Focus the editor below.
map <C-w>j <Cmd>SVPress <LT>D-j><CR><Cmd>SVPress j<CR><Cmd>SVPress <LT>CR><CR>
" Focus the editor above.
map <C-w>k <Cmd>SVPress <LT>D-j><CR><Cmd>SVPress k<CR><Cmd>SVPress <LT>CR><CR>
" Focus the editor on the right.
map <C-w>l <Cmd>SVPress <LT>D-j><CR><Cmd>SVPress l<CR><Cmd>SVPress <LT>CR><CR>
" Rotate the source editors.
map <C-w>w <Cmd>SVPress <LT>C-`><CR>
```

### Folds

Xcode's folding capabilities are limited, but you get the basics with these bindings:

```viml
map zc <Cmd>SVPress <LT>M-D-Left><CR>
map zo <Cmd>SVPress <LT>M-D-Right><CR>
map zM <Cmd>SVPress <LT>M-S-D-Left><CR>
map zR <Cmd>SVPress <LT>M-S-D-Right><CR>
```

### Opening third-party applications

You can get pretty creative with key bindings. Here's one opening [Sourcetree](https://www.sourcetreeapp.com/) with <kbd>&lt;leader>st</kbd> for the current Git repository, using `!` to execute a shell command and `%` to get the path of the edited file.

```viml
map <leader>st <Cmd>silent !stree "%"<CR>
```

This keybinding opens a new iTerm tab at the root of the Git repository for the current buffer.

```viml
map <leader>sh <Cmd>silent !open -a iTerm `(cd "%:p:h"; git rev-parse --show-toplevel)`<CR>
```

## Attributions

Thanks to [kindaVim](https://kindavim.app/) and [SketchyVim](https://github.com/FelixKratz/SketchyVim) for showing me this was possible.

* [Neovim](https://github.com/neovim/neovim), duh.
* [Sparkle](https://sparkle-project.org/) provides the auto-updater.
* [MessagePack.swift](https://github.com/a2/MessagePack.swift) is used to communicate with Neovim using MessagePack-RPC.
* [Sauce](https://github.com/Clipy/Sauce) helps supporting virtual keyboard layouts.
* [NSLogger](https://github.com/fpillet/NSLogger) for keeping me sane while debugging.
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates the project, because `.xcodeproj` is meh.

