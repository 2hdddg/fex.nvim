local api = vim.api
local M = {}

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
    local diredOptions = table.remove(lines) -- options
    local diredOffsets = table.remove(lines) -- offsets
    -- Tidy up the offsets to be more usable
    -- Remove the prefix and split into array of strings where each string is a number
    diredOffsets = vim.split(diredOffsets:gsub("//DIRED// ", ""), " ")
    -- lines now looks something like this:
    --  total 12
    --  drwxrwxr-x  2 peter peter 4096 sep  9 11:08 .
    --  drwxr-xr-x 79 peter peter 4096 sep  9 09:55 ..
    --  -rw-rw-r--  1 peter peter 2660 sep  9 11:08 dired.lua
    local indexOfFirstFile = 2 -- Index of . line above
    -- Compose a nice table to consume
    return {
        lines = lines,
        diredOptions = diredOptions,
        diredOffsets = diredOffsets,
        indexOfFirstFile = indexOfFirstFile,
    }
end

local function render(buf, ns, path, lsResult)
    api.nvim_buf_set_option(buf, 'modifiable', true)
    -- Clear existing lines
    api.nvim_buf_set_lines(buf, 0, -1, false, {})
    -- Write lines
    local lines = lsResult.lines
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    -- Now loop through each line and mark the position of the filenames,
    -- this is needed to be able to find the filename when navigating and
    -- to make a pretty highlight
    local runningOffset = 0
    local diredOffsets = lsResult.diredOffsets
    for k, v in pairs(lines) do
        local len = string.len(v)
        if k >= lsResult.indexOfFirstFile then
            -- nvim_buf_get_extmark uses zero based lines and columns
            local start = tonumber(table.remove(diredOffsets, 1)) - runningOffset
            local stop = tonumber(table.remove(diredOffsets, 1)) - runningOffset
            -- Use netrw highlights, netrwDir, netrwExe
            -- As long as long listing is used this will work
            local highlight = "netrwExe"
            local typeChar = string.sub(v, 3, 3)
            if typeChar == 'd' then
                highlight = "netrwDir"
            end
            if typeChar == 'l' then
                highlight = "netrwLink" -- netrwLink for --> and netRwSymlink for rest
            end
            api.nvim_buf_set_extmark(buf, ns, k - 1, start, {
                end_row = k - 1,
                end_col = stop,
                hl_group = highlight,
            })
        end
        -- Plus one for newline character
        runningOffset = runningOffset + len + 1
    end
    api.nvim_buf_set_option(buf, 'modifiable', false)
end

local function createBuffer()
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    api.nvim_buf_set_option(buf, 'filetype', 'dired')
    return buf
end

local function isDiredBuffer(buf)
    return true
end

local function getPathFromLine(buf, ns, line)
    local name = getNameFromLine(buf, ns, line)
    return name
end

local function getNameFromLine(buf, ns, line)
    local marks = api.nvim_buf_get_extmarks(buf, ns, line - 1, line - 1, {details = true})
    local mark = marks[1]
    local startCol = mark[3]
    local details = mark[4]
    local endCol = details["end_col"]
    local name = api.nvim_buf_get_text(buf, line - 1, startCol, line - 1, endCol, {})
    return name
end

local function getNamespace()
    return api.nvim_create_namespace('dired')
end

M.open = function()
    -- Create a new buffer and attach it to the current window
    local buf = createBuffer()
    local win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
    -- Ensure namespace exists and clean it up
    local ns  = getNamespace()
    api.nvim_buf_clear_namespace(buf, -1, 0, -1)
    local path = ".."
    -- Note that this is not guaranteed to be unique TODO
    api.nvim_buf_set_name(buf, "dired " .. path)
    -- Get files and directories
    local lsResult = ls(path)
    -- Render it
    render(buf, ns, path, lsResult)
end

M.enter = function()
    local buf = api.nvim_get_current_buf()
    if not isDiredBuffer(buf) then
        return
    end
    local ns = getNamespace()
    local win = api.nvim_get_current_win()
    local pos = api.nvim_win_get_cursor(win)
    local path = getPathFromLine(buf, ns, pos[1])
end

return M
