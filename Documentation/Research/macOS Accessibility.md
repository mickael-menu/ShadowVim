# macOS Accessibility

## Scrolling an element

Some apps don't update the text area scroll when moving the caret (e.g. with hjkl keys in normal mode). While it works with Xcode, it doesn't with TextEdit. A lead to address this is to manually scroll the screens with [`kAXVisibleCharacterRangeAttribute`](https://developer.apple.com/documentation/applicationservices/kaxvisiblecharacterrangeattribute). This API could also be useful to implement `zt` and such.

## File path

Neovim requires the file path to determine the `filetype`. We can get it using the `kAXDocumentAttribute` on the document window.
