# Keyboard

Keyboard events are *hard*. Depending on the active input source (keyboard layout), you might not get the key code you expect.

Once you get past this hurdle (credits to [Sauce](https://github.com/Clipy/Sauce)), you have to decide what to do with each keystroke:

* Should you send it directly to Nvim? Even if it's Shift-8 and the user expect to input `*`?
* Should it be handled by Xcode instead? Probably expected for most command-based keyboard shortcuts.
* Should you interpret the unicode character depending on the keyboard layout to send it as Nvim input? For example, if the user hit Option-G to insert a `©`. But if you do, then Nvim can't remap this keyboard shortcut.

Eventually, ShadowVim should offer a way to customize for each keyboard shortcut (and a fallback for each modifier) the strategy:

* Send character to Nvim
* Send keystroke to Nvim
* Send keystroke to UI

In the meantime, this hard-coded strategy might be enough for most use cases:

* If there's a command modifier, send to UI.
* If there's a control modifier OR if it's a non printable character, send the keystroke to Nvim.
* Otherwise, send the character to Nvim.
