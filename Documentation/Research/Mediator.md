# Mediator Nvim <-> Xcode

## Insert mode

The insert mode can be handled either by Nvim, or by Xcode directly.

### Insert mode handled by Nvim

* Potentially slow, as every keystroke result in a `buf_lines_event` sent by Nvim and applied to Xcode.
    * It's pretty seamless on my M1 MacBook Air, but might not always be, especially on Intel.
* A lot of stuff will work out of the box:
    * insert-specific key bindings
    * better undo tree
    * replace mode (`R`)
* It breaks easily when using external features, such as the Xcode completion pop-up.

### Insert mode handled by Xcode

This is the approach used by [`vscode-neovim`](https://github.com/vscode-neovim/vscode-neovim).

* Much better performance, as there are no back and forth between Neovim and Xcode.
* Xcode's completion pop-up will work without issues.
* We need to synchronize the buffer again with Neovim, potentially breaking the undo tree.
* Neovim features for the Insert mode will need to be reimplemented for Xcode.
* Dot-repeat is broken and requires complex workarounds, see:
    * https://github.com/vscode-neovim/vscode-neovim/pull/173
    * https://github.com/vscode-neovim/vscode-neovim/issues/209
    * A workaround could be to let Neovim handle Insert mode when triggered from operator pending mode ([suggestion from justinmk](https://github.com/vscode-neovim/vscode-neovim/issues/76#issuecomment-562902179)).
    * [Using a macro is also a partial workaround](https://github.com/vscode-neovim/vscode-neovim/issues/76#issuecomment-568910666).
