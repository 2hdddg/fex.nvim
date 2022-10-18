# fex.nvim
Neovim file explorer based on ideas from Emacs dired plugin and Vims very own netrw.

Basic idea is that listed files and directories should behave like read only vim buffer.

Files and directories are displayed by ls command and parsed through ls dired support.

Install with plug:
  Plug '2hdddg/fex.nvim'

Setup is currently optional and only provides option to set parameters to ls command.

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
* % to create new file in current directory
* d to create new directory in current directory
* D to delete file or directory
* R to rename current directory or file
* Y yanks full path of the current file or directory
* C-z switches to a terminal with cwd set to the path of the current directory or file

Currently planned to implement in this order:
* Support multiple views corresponding to different ls invocations (sorts, attrs)
* Recursive rendering of subdirectories with indentation to a specified depth (not relying on ls -R)
* Folding of above
* Open file/directory in vsplit/split without attaching preview to it
* Configurable keymaps
* Configurable color scheme
