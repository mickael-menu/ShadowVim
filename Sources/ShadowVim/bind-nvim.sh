#!/bin/sh

# Launches a new Nvim instance that will bind its UI to the ShadowVim embedded
# Nvim. This can be used to debug issues with the embedded Nvim.
nvim --server /tmp/shadowvim.pipe --remote-ui
