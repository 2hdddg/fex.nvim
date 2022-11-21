# fex.nvim
Neovim file explorer based on ideas from Emacs dired plugin and Vims very own netrw. Basic idea is that listed files and directories should behave like read only vim buffer. Files and directories are displayed by ls command and parsed through ls dired support.

![simple](https://user-images.githubusercontent.com/162010/203120608-eb0b01c7-fd64-4811-9186-470385ee9199.png)

![symlinks](https://user-images.githubusercontent.com/162010/203120640-a8cca8c2-5de5-4e9d-92e2-0ce918a17486.png)

## Installation

Install with plug:
  Plug '2hdddg/fex.nvim'

## Configuration

Configuration is currently optional and only provides option to set parameters to ls command.

```lua
require("fex").setup({ls = "-al"})
```

Default ls listing is based on output with option as set:
```lua
ls = "-ahl --group-directories-first --time-style="long-iso"
```

ls option must contain -l for dired data to become available.

## Usage

To start browsing files in directory of current:
```lua
require("fex").open()
```

To start browsing a specific direcory:
```lua
require("fex").open('/a/specific/directory')
```

## Keybindings

In the file browser the following keymaps are available (currently not configurable):
* `<CR>` to step into directory or open file in Fex window
* `v` to open preview of directory or file in vertical split window
* `s` to open preview of directory or file in split window
* `-` to step into parent directory
* `%` to create new file in current directory
* `d` to create new directory in current directory
* `D` to delete file or directory
* `R` to rename current directory or file
* `Y` yanks full path of the current file or directory
* `C-z` switches to a terminal with cwd set to the path of the current directory or file

## Future

Currently planned to implement in this order:
* Support multiple views corresponding to different ls invocations (sorts, attrs)
* Recursive rendering of subdirectories with indentation to a specified depth (not relying on ls -R)
* Folding of above
* Open file/directory in vsplit/split without attaching preview to it
* Configurable keymaps
* Configurable color scheme
