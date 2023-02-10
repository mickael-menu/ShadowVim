# macOS Accessibility

## Scrolling an element

Some apps don't update the text area scroll when moving the caret (e.g. with hjkl keys in normal mode). While it works with Xcode, it doesn't with TextEdit. A lead to address this is to manually scroll the screens with [`kAXVisibleCharacterRangeAttribute`](https://developer.apple.com/documentation/applicationservices/kaxvisiblecharacterrangeattribute). This API could also be useful to implement `zt` and such.

## File path

Neovim requires the file path to determine the `filetype`. We can get it using the `kAXDocumentAttribute` on the document window.

## Converting between line numbers and character indices

Some APIs might do it for us, like [`rangeForLine`](https://developer.apple.com/documentation/appkit/deprecated_symbols/nsaccessibility/text-specific_parameterized_attributes).

## Observing current application

We can use `NSWorkspace.didActivateApplicationNotification` to be notified when the current application changes.

## Reading `AXClassName` attributes

Unfortunately, we can't read the class of `AXUIElement`s without a special Apple entitlement.

https://stackoverflow.com/questions/45590888/how-to-get-the-objective-c-class-name-corresponding-to-an-axuielement
