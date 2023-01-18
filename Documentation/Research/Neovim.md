# Neovim

## Swap files

Swap files might be troublesome in this use case. We can use `set noswapfile` or `nvim -n` to disable them.

## RPC requests

To send a synchronous RPC request, we need to get the channel used for IO. Use `nvim_get_api_info` to get it.

## Capturing the output of a command

Use `redir`, e.g.

```
redir! >/tmp/output
echo unknown
redir END
```

This could be used with `CmdlineEnter` and `CmdlineLeave` to automatically capture the output of individual commands. 

Is there an event sent after a command is executed? Can't find any, so might need to add a delay.

An alternative could be to discard the cmdline on `<CR>` (or `CmdlineLeave` with `abort`) and call the command manually with `exec()` with `output: true`.

## Preventing commands

Set `abort = true` when receiving `CmdlineLeave`.

```viml
autocmd CmdlineLeave * let v:event.abort=v:true
```

Note that this will not work if a command is called with `<Cmd>`.
