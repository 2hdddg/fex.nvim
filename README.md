# fex.nvim
Neovim file explorer based on Emacs dired plugin, very similair to netrw.
Files and directories are displayed by ls command and parsed through ls dired support
in a standard vim buffer which makes it easy to navigate and copy stuff.

Install with plug:
  Plug '2hdddg/fex.nvim'

Setup is currently optional and only provides option to set parameters to ls command

require("fex").setup({ls = "-al"})

Default ls listing is based on output with option as set:
    ls = "-ahl --group-directories-first --time-style="long-iso"

ls option must contain -l for dired data to become available.

To start browsing current buffers directory, run command Fex or
    require("fex").open("/whatever/file_or_directory", {ls = "-l"})
Wehere both path and options are optional. If path is not specified path to current buffer is used.

In the file browser the following keymaps are available (currently not configurable):
* <CR> to step into directory or open file in Fex window
* v to open preview of directory or file in vertical split window
* s to open preview of directory or file in split window
* - to step into parent directory

Current Limitations being wokred on:
* No operations like deletes, move, create file/directory
* Hardcoded color scheme, based on netrw
