local M = {}
local api = vim.api
-- Use netrw highlights, netrwDir, netrwExe
local lsTypeToHighlight = {
    d = "netrwDir",
    l = "netrwLink",
    f = "netrwExe",
}
local statTypeTolsType = {
    dir = "d",
    file = "f",
    link = "l",
}
local id = 0
local highlightToLsType = {}
for k, v in pairs(lsTypeToHighlight) do
    highlightToLsType[v] = k
end
local indexOfFirstFile = 3 -- Line in buffer containing first file (.)

local function ls(path)
    -- Invoke hardcoded ls command and split it into lines
    -- The D option enables special dired output that is needed to avoid parsing filenames
    local output = api.nvim_exec("!ls -ahlD --group-directories-first --time-style=\"long-iso\" " .. path, true)
    local lines = vim.split(output, "\n")
    -- Tidy up
    table.remove(lines, 1) -- Contains the ls command
    table.remove(lines, 1) -- Empty
    table.remove(lines)    -- Last line is also empty
    -- Parse the dired output
    -- Ignore stuff in the end, seems to get some error output there sometimes
    local foundDired
    local diredOptions
    while not foundDired do
        diredOptions = table.remove(lines) -- options
        foundDired = string.sub(diredOptions, 1, 8) == "//DIRED-"
    end
    local diredOffsets = table.remove(lines) -- offsets
    -- Tidy up the offsets to be more usable
    -- Remove the prefix and split into array of strings where each string is a number
    diredOffsets = vim.split(diredOffsets:gsub("//DIRED// ", ""), " ")
    -- lines now looks something like this:
    --
    --  total 12
    --  drwxrwxr-x  2 peter peter 4096 sep  9 11:08 .
    --  drwxr-xr-x 79 peter peter 4096 sep  9 09:55 ..
    --  -rw-rw-r--  1 peter peter 2660 sep  9 11:08 dired.lua
    --
    -- Adjust initial offset to include "total 12"
    local initialDiredOffset = string.len(lines[1]) + 1 -- Plus one for newline
    -- Add the current path first
    table.insert(lines, 1, path)
    -- Compose a nice table to consume
    return {
        lines = lines,
        diredOptions = diredOptions,
        diredOffsets = diredOffsets,
        initialDiredOffset = initialDiredOffset,
    }
end

local function getLsTypeFromLine(line)
    -- As long as long listing is used this will work
    local c = string.sub(line, 3, 3)
    if c == '-' then
        c = 'f'
    end
    return c
end

local function render(buf, ns, path, lsResult)
    api.nvim_buf_set_option(buf, 'modifiable', true)
    -- Clear existing lines
    api.nvim_buf_set_lines(buf, 0, -1, false, {})
    -- Clear highlights
    api.nvim_buf_clear_namespace(buf, -1, 0, -1)
    -- Write lines
    local lines = lsResult.lines
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    -- Highlight first line containing current directory
            api.nvim_buf_set_extmark(buf, ns, 0, 0, {
                end_row = 0,
                end_col = string.len(lines[1]),
                hl_group = lsTypeToHighlight['d'],
            })
    -- Now loop through each line and mark the position of the filenames,
    -- this is needed to be able to find the filename when navigating and
    -- to make a pretty highlight
    local runningOffset = lsResult.initialDiredOffset
    local diredOffsets = lsResult.diredOffsets
    for k, v in pairs(lines) do
        local len = string.len(v)
        if k >= indexOfFirstFile then
            -- nvim_buf_get_extmark uses zero based lines and columns
            local start = tonumber(table.remove(diredOffsets, 1)) - runningOffset
            local stop = tonumber(table.remove(diredOffsets, 1)) - runningOffset
            local typeChar = getLsTypeFromLine(v)
            api.nvim_buf_set_extmark(buf, ns, k - 1, start, {
                end_row = k - 1,
                end_col = stop,
                hl_group = lsTypeToHighlight[typeChar],
            })
            -- Plus one for newline character
            runningOffset = runningOffset + len + 1
        end
    end
    api.nvim_buf_set_option(buf, 'modifiable', false)
end

local function createBuffer()
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    api.nvim_buf_set_option(buf, 'filetype', 'fex')
    api.nvim_buf_set_var(buf, "preview", nil)
    return buf
end

local function isDiredBuffer(buf)
    return true
end

local function getRootPath(buf)
    return api.nvim_buf_get_text(buf, 0, 0, 0, -1, {})[1]
end

local function getInfoFromLine(buf, ns, line)
    local marks = api.nvim_buf_get_extmarks(buf, ns, {line - 1, 0}, {line - 1, -1}, {details = true})
    local mark = marks[1]
    local startCol = mark[3]
    local details = mark[4]
    local endCol = details["end_col"]
    local highlight = details["hl_group"]
    local name = api.nvim_buf_get_text(buf, line - 1, startCol, line - 1, endCol, {})[1]
    return {
        root = getRootPath(buf),
        name = name,
        lsType = highlightToLsType[highlight],
    }
end

local function openPath(buf, ns, path)
    id = id + 1
    api.nvim_buf_set_name(buf, "fex " .. path .. " " .. id)
    -- Get files and directories
    local lsResult = ls(path)
    -- Render it
    render(buf, ns, path, lsResult)
end

local function getLsTypeFromFtype(path)
    local ftype = vim.fn.getftype(path)
    if ftype == nil then
        return nil
    end
    return statTypeTolsType[ftype]
end

local function enter(buf, ns, onFile, onDir)
    -- Find out the path that corresponds to the current line
    local win = api.nvim_get_current_win()
    local pos = api.nvim_win_get_cursor(win)
    local line = pos[1]
    if line < indexOfFirstFile then
        return
    end
    local info = getInfoFromLine(buf, ns, line)
    -- Check if it is a directory, file or link
    if info.lsType == "d" then
        onDir(info)
    elseif info.lsType == "f" then
        onFile(info)
    else
        print(info.lsType)
    end
end

local function addToPath(path, toAdd)
    if toAdd == "." then
        return path
    end
    if toAdd == ".." then
        return vim.fn.fnamemodify(path, ":h")
    end
    return path .. "/" .. toAdd
end

local function closePreview(buf)
    local previewWin = api.nvim_buf_get_var(buf, "preview")
    if previewWin == nil then
        return
    end
    if not api.nvim_win_is_valid(previewWin) then
        return
    end
    api.nvim_win_hide(previewWin)
end

local function openPreview(win, buf, cmd, inNewWindow)
    closePreview(buf)
    vim.cmd(cmd)
    local newWin = api.nvim_get_current_win()
    inNewWindow()
    -- Keep focus in file explorer
    api.nvim_set_current_win(win)
    api.nvim_buf_set_var(buf, "preview", newWin)
end

local function setKeymaps(win, buf, ns)
    api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
        desc = "Enter directory or open file",
        callback = function()
            enter(buf, ns,
                -- Open file in current window
                function(info)
                    vim.cmd('e ' .. addToPath(info.root, info.name))
                end,
                -- Open directory in current window
                function(info)
                    openPath(buf, ns, addToPath(info.root, info.name))
                end)
        end
    })
    api.nvim_buf_set_keymap(buf, 'n', 'v', '', {
        desc = "Open directory or file in vsplit",
        callback = function()
            enter(buf, ns,
                -- Open file in vs preview window
                function(info)
                    openPreview(win, buf, 'vs ' .. addToPath(info.root, info.name),
                        function()
                        end)
                end,
                -- Open directory in vs preview window
                function(info)
                    openPreview(win, buf, 'vs',
                        function()
                            M.open(addToPath(info.root, info.name))
                        end)
                end)
        end
    })
    api.nvim_buf_set_keymap(buf, 'n', '-', '', {
        desc = "Step up",
        callback = function()
            local rootPath = getRootPath(buf)
            M.open(vim.fn.fnamemodify(rootPath, ":h"))
        end
    })
end

M.open = function(path)
    if path == nil then
        path = vim.fn.expand("%:p")
    end
    local lsType = getLsTypeFromFtype(path)
    if lsType == nil then
        return
    end
    local filename = nil
    if lsType == "f" then
        -- Extract filename
        filename = vim.fn.fnamemodify(path, ":t")
    end
    -- Expand to full path
    path = vim.fn.fnamemodify(path, ":p:h")
    -- Ensure namespace exists
    local ns  = api.nvim_create_namespace('fex')
    -- Create a new buffer and attach it to the current window
    local buf = createBuffer()
    local win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
    setKeymaps(win, buf, ns)
    openPath(buf, ns, path)
end

return M
