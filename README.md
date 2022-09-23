# fex.nvim
Neovim file explorer based on Emacs dired plugin, very similair to netrw.
Files and directories are displayed by ls command and parsed through ls dired support
in a standard vim buffer which makes it easy to navigate and copy stuff.

Install with plug:
  Plug '2hdddg/fex.nvim'

Setup is currently optional and only provides option to set parameters to ls command

require("fex").setup({})

Default ls listing is based on output with option as set:
    lsArgs = "-ahl --group-directories-first --time-style="long-iso"

To start browsing current buffers directory, run command Fex

In the file browser the following keymaps are available (currently not configurable):
* <CR> to step into directory or open file in Fex window
* v to open preview of directory or file in vertical split window
* s to open preview of directory or file in split window
* - to step into parent directory

Current Limitations:
* Symbolic links does not work
* No way to do operations on files like deletes, move, create file/directory
* Hardcoded color scheme, based on netrw
