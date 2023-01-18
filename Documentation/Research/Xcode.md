# Xcode

## Prevent Xcode from indenting the code

To avoid conflicts between Xcode and Nvim's auto indentation, Xcode's should be disabled. We can check it out with `defaults read -app xcode`.

Adjust the `textwidth` ruler to the one set in Xcode?

```
defaults write com.apple.dt.Xcode DVTTextPageGuideLocation -int 120
```

https://github.com/robb/dotfiles/blob/main/xcode/settings.install

## Color scheme

The color scheme from Xcode (`defaults read -app xcode`) could be used for the ShadowVim status bar.
