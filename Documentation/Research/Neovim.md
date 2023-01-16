# Neovim

## Swap files

Swap files might be troublesome in this use case. We can use `set noswapfile` or `nvim -n` to disable them.

## RPC requests

To send a synchronous RPC request, we need to get the channel used for IO. Use `nvim_get_api_info` to get it.

