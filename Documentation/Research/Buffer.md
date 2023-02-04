# Bidirectional buffer synchronization

While there are two live buffers for any document (Nvim and UI), there is no natural "source of truth" for the document content. Changes mostly come from Nvim, but in some cases we want to synchronize changes from the UI back to Nvim:

* Auto-completion of symbols and snippets.
* Paste using macOS clipboard through Cmd-V or "Paste" menu.
* Undo/redo using the UI instead of `u`/`^R`.
* Maybe Xcode auto-formatting, when it's enabled in the preferences. Although this one can conflict with Nvim.

## Token

To address this, let's introduce a shared "buffer token" whose owner temporarily becomes the source of truth.

* The **main buffer** is the buffer currently owning the token and is the source of truth for the content.
* The **subordinate buffer** is the alternate buffer that will apply the changes from the owner buffer.
* The buffers are **idle** when none of them owns the token.
* A *subordinate* buffer is **frozen** when receiving conflicting change events. It will be resynchronized and unfrozen when the token is released by the *main* buffer.

### Ownership flow

The token is automatically acquired – if free – when changes are made in one of the buffers (UI or Nvim). While the token is acquired, all partial changes from the *main* buffer are sent to the *subordinate*, whose changes are temporarily ignored. After a short delay (debounce) without changes from *main*, the token is released and a final buffer-wide synchronization from *main* to *subordinate* is made to ensure the content is the same.

## Partial changes synchronization

This synchronization occurs when the *main* buffer emits events for discrete changes.

To prevent messing up the *subordinate* buffer with garbage events, partial changes are only applied if the content of the *subordinate* is the same as the content of *main* before the change. If it's not the case, the *subordinate* will become *frozen* until the token is released and the buffer-wide synchronization is triggered.

## Buffer-wide synchronization

This synchronization occurs when the token is released by the *main* buffer. This is a sanity check to make sure that the two buffers are fully synchronized when *idle*.

When triggered, the whole content of the formerly *main* buffer is applied to the *subordinate* buffer. A diffing algorithm is used to edit only the conflicting lines, to avoid weird scrolling artifacts in the UI buffer.

Finally, the cursor is finally repositioned in the *subordinate* to match the *main* buffer.

## Cursor synchronization

While a *subordinate* buffer is not *frozen*, any cursor event from *main* is applied to it.

## Scroll synchronization

The UI buffer is the only source of truth for the scrolling state. Therefore, scroll changes in Nvim (for example triggered by `zz`, `zt`, etc.) are ignored and must be implemented natively in the UI buffer.
