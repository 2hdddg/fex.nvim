local api = vim.api

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
end

local function init()
    local buf = api.nvim_win_get_buf(0)
    --api.nvim_create_buf(false, true)
    --
    -- Ensure namespace exists and clean it up
    local ns  = api.nvim_create_namespace('dired')
    api.nvim_buf_clear_namespace(buf, -1, 0, -1)
    local path = ".."
    -- Get files and directories
    local lsResult = ls(path)
    -- Render it
    render(buf, ns, path, lsResult)
end


api.nvim_command("botright split new")
init()


--local a   = vim.api
--local pos = a.nvim_win_get_cursor(0)
--local ns  = a.nvim_create_namespace('my-plugin')
--print(ns)
-- Create new extmark at line 1, column 1.
--local m1  = a.nvim_buf_set_extmark(0, ns, 0, 0, {})
--print(m1)
-- Create new extmark at line 3, column 2.
--local opts = {end_row = 2}
--local m2  = a.nvim_buf_set_extmark(0, ns, 2, 1, opts)
--print(m2)
-- Get extmarks only from line 3.
--local ms  = a.nvim_buf_get_extmarks(0, ns, {1,0}, {-1,-1}, {details = true})
--print(vim.inspect(ms))
-- Get all marks in this buffer + namespace.
--local all = a.nvim_buf_get_extmarks(0, ns, 0, -1, {})
--print(vim.inspect(all))
--local xm =a.nvim_buf_get_extmark_by_id(0, ns, m2, {details = true})
--print(vim.inspect(xm))
