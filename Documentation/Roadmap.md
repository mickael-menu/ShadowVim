# Roadmap

## 0.1

* Switch between multiple buffers
* Bidirectional changes synchronization
* Bidirectional cursor synchronization
* Fix auto-completion pop-up
* Dedicated user configuration file
    * `g:svim` variable

## Backlog

* Visual mode feedback
* `XDG_CONFIG_HOME` support for the user configuration file
* Logger
* Auto-updater
* Preferences panel
    * Launch on startup
    * Auto disable conflicting Xcode settings (e.g. auto pairing, indentation)
    * Auto adjust the Xcode ruler to match `textwidth`
* Optimize applying `buf_lines_event`
    * Replace only changed portions of a line
    * Use parameterized attributes to compute character offsets
* Support two buffers of the same file
* Attach to Neovim UI events to externalize:
    * the command line
    * messages
    * pop-up menus
    * highlights (?)
* API to query and interact with accessible UI elements
* API to trigger Xcode features
    * Fix-it suggestions
* Override basic built-in Ex commands conflicting with Xcode (e.g. `e`, `w`, `sav`, `q`)
* Override bindings:
    * `K`-  open Xcode's documentation (right click > Show Quick Help or the full Documentation app?)
    * `gd` - go to the definition of a type
    * folds
* Override split/window Ex commands and bindings
* Override scrolling Ex commands and bindings (e.g. `zz`, `zt`)
* Override tab Ex commands and bindings
* External display of read-only buffers (e.g. triggered by `:help`)
    * Use current Xcode color scheme
* VimL/Lua bridge to native APIs
* API for graphic decorations (e.g. [vim-easymotion](https://github.com/easymotion/vim-easymotion))
* Support for multiple applications as VimL/Lua extensions
* Bindings for UI interactions in non-text area elements
