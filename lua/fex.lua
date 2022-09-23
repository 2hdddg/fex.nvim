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
local globalOptions = {
    lsArgs = "-ahl --group-directories-first --time-style=\"long-iso\""
}

local function ls(path, options)
    -- Invoke ls command and split it into lines
    -- The D option enables special dired output that is needed to avoid parsing filenames
    local lsCmd = "ls -D " .. options.lsArgs .. " " .. path
    local h = io.popen(lsCmd)
    local output = h:read("*a")
    h:close()
    local lines = vim.split(output, "\n")
    -- Parse the dired output
    -- Ignore empty stuff in the end
    local foundDired
    local diredOptions
    while not foundDired do
        diredOptions = table.remove(lines) -- options
        foundDired = string.sub(diredOptions, 1, 8) == "//DIRED-"
    end
    local diredOffsets = table.remove(lines) -- offsets
    -- lines now looks something like this:
    --
    --  total 12
    --  drwxrwxr-x  2 peter peter 4096 sep  9 11:08 .
    --  drwxr-xr-x 79 peter peter 4096 sep  9 09:55 ..
    --  -rw-rw-r--  1 peter peter 2660 sep  9 11:08 dired.lua
    --
    -- Tidy up the offsets to be more usable
    -- Remove the prefix and split into array of strings where each string is a number
    diredOffsets = vim.split(diredOffsets:gsub("//DIRED// ", ""), " ")
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

local function render(win, buf, ns, path, lsResult, optionalFilename)
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
    local line = indexOfFirstFile
    local start
    for k, v in pairs(lines) do
        local len = string.len(v)
        if k >= indexOfFirstFile then
            -- nvim_buf_get_extmark uses zero based lines and columns
            start = tonumber(table.remove(diredOffsets, 1)) - runningOffset
            local stop = tonumber(table.remove(diredOffsets, 1)) - runningOffset
            local typeChar = getLsTypeFromLine(v)
            col = start
            api.nvim_buf_set_extmark(buf, ns, k - 1, start, {
                end_row = k - 1,
                end_col = stop,
                hl_group = lsTypeToHighlight[typeChar],
            })
            if optionalFilename ~= nil then
                local name = string.sub(v, start+1, stop)
                if name == optionalFilename then
                    line = k
                    optionalFilename = nil
                end
            end
            -- Plus one for newline character
            runningOffset = runningOffset + len + 1
        end
    end
    api.nvim_win_set_cursor(win, {line, start})
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

local function openPath(win, buf, ns, path, optionalFilename, options)
    id = id + 1
    api.nvim_buf_set_name(buf, "fex " .. path .. " " .. id)
    -- Get files and directories
    local lsResult = ls(path, options)
    -- Render it
    render(win, buf, ns, path, lsResult, optionalFilename)
end

local function getLsTypeFromFtype(path, options)
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

local function setKeymaps(win, buf, ns, options)
    -- Preview utility function, set cmd to vs or sp
    local function preview(cmd)
        enter(buf, ns,
            -- Open file in preview window
            function(info)
                openPreview(win, buf, cmd .. " " .. addToPath(info.root, info.name),
                    function()
                    end)
            end,
            -- Open directory in preview window
            function(info)
                openPreview(win, buf, cmd,
                    function()
                        M.open(addToPath(info.root, info.name))
                    end)
            end)
    end

    keymaps = {
        {
            keys = "<CR>",
            desc = "Step into directory or open file in current window",
            func = function()
                enter(buf, ns,
                    -- Open file in current window
                    function(info)
                        vim.cmd('e ' .. addToPath(info.root, info.name))
                    end,
                    -- Open directory in current window
                    function(info)
                        openPath(win, buf, ns, addToPath(info.root, info.name), nil, options)
                    end)
            end,
        },
        {
            keys = "v",
            desc = "Open preview of directory or file in vertical split window",
            func = function() preview("vs") end,
        },
        {
            keys = "s",
            desc = "Open preview of directory or file in split window",
            func = function() preview("sp") end,
        },
        {
            keys = "-",
            desc = "Step into parent directory",
            func = function()
                local rootPath = getRootPath(buf)
                local name = vim.fn.fnamemodify(rootPath, ":t")
                local parentPath = vim.fn.fnamemodify(rootPath, ":h")
                openPath(win, buf, ns, parentPath, name, options)
            end,
        },
    }
    for i = 1, #keymaps do
        m = keymaps[i]
        api.nvim_buf_set_keymap(buf, 'n', m.keys, '', {
            desc = m.desc,
            callback = m.func,
        })
    end
end

local function mergeOptions(defaults, overrides)
    local options = {}
    if overrides == nil then
        return defaults
    end
    for k, v in pairs(defaults) do
        if overrides[k] then
            options[k] = overrides[k]
        else
            options[k] = v
        end
    end
    return options
end

M.open = function(path, options)
    options = mergeOptions(globalOptions, options)
    if path == nil then
        path = vim.fn.expand("%:p")
    end
    local lsType = getLsTypeFromFtype(path, options)
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
    setKeymaps(win, buf, ns, options)
    openPath(win, buf, ns, path, filename, options)
end

M.setup = function(options)
    globalOptions = mergeOptions(globalOptions, options)
end

return M
