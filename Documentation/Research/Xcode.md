# Xcode

## Prevent Xcode from indenting the code

To avoid conflicts between Xcode and Nvim's auto indentation, Xcode's should be disabled. We can check it out with `defaults read -app xcode`.

Adjust the `textwidth` ruler to the one set in Xcode?

```
defaults write com.apple.dt.Xcode DVTTextPageGuideLocation -int 120
```

We can also use this to switch on/off Xcode's default Vim bindings:
```
defaults write -app xcode KeyBindingsMode -string Default
defaults write -app xcode KeyBindingsMode -string Vi
```

https://github.com/robb/dotfiles/blob/main/xcode/settings.install

## Color scheme

The color scheme from Xcode (`defaults read -app xcode`) could be used for the ShadowVim status bar.

## Completion popup

When the Xcode completion popup is visible, we need to intercept the `<CR>` key and also apply the completed changes back to Neovim's buffer.

To identify the popup, we can look for the `selectedRowsChanged` AX event for an element with an identifier `_XC_COMPLETION_TABLE_`. When the completion popup is dismissed, and its `visibleRows` is empty. The Accessibility Inspector indicates that this element has the class `DVTTextCompletionTableView`.

## Fix-it suggestions

When a fix-it is suggested by Xcode, we can look for the matching element (class `SourceEditor.LineAnnotationAccessibility`) and perform the Press action to trigger it.

## Position of the source editors

The `position` and `size` AX attributes seem to return incorrect values with Xcode. We can get the proper one by querying the text area's parents.

## Command line

Integrate it directly in Xcode's UI?
