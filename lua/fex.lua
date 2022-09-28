local M = {}
local api = vim.api
local id = 0
local globalOptions = {
    ls = "-ahl --group-directories-first --time-style=\"long-iso\""
}
local render = require("render").render
local paths = require("paths")

local function createBuffer(options)
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    api.nvim_buf_set_option(buf, 'filetype', 'fex')
    api.nvim_buf_set_var(buf, "options", options)
    api.nvim_buf_set_var(buf, "preview", nil)
    return buf
end

local function getLines(ctx)
    return api.nvim_buf_get_var(ctx.buf, "lines")
end

local function currentLineNumber(ctx)
    return api.nvim_win_get_cursor(ctx.win)[1]
end

local function getRoot(ctx)
    local lines = getLines(ctx)
    local lineNumber = currentLineNumber(ctx)
    while lineNumber > 0 do
        local line = lines[lineNumber]
        if line.isRoot then
            return line
        end
        lineNumber = lineNumber - 1
    end
end

local function open(ctx, path, optionalFilename)
    id = id + 1
    api.nvim_buf_set_name(ctx.buf, "fex " .. path .. " " .. id)
    local lines = render(ctx, path, optionalFilename)
    -- Store data about the parsed lines in buffer variable
    api.nvim_buf_set_var(ctx.buf, "lines", lines)
end

local function getCurrent(ctx)
    local curr = getLines(ctx)[currentLineNumber(ctx)]
    -- Patch things together in a non-standard way..
    curr.root = getRoot(ctx)
    if curr.isRoot then
        curr.fullPath = curr.root.name
    else
        curr.fullPath = paths.add(curr.root.name, curr.name)
    end
    return curr
end

local function enter(ctx, onFile, onDir)
    local curr = getCurrent(ctx)
    if curr.isLink then
        path = curr.linkPath
    end
    if curr.isDir then
        onDir(curr.fullPath)
    else
        onFile(curr.fullPath)
    end
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

local function openPreview(ctx, cmd, inNewWindow)
    closePreview(ctx.buf)
    vim.cmd(cmd)
    local newWin = api.nvim_get_current_win()
    inNewWindow()
    -- Keep focus in file explorer
    api.nvim_set_current_win(ctx.win)
    api.nvim_buf_set_var(ctx.buf, "preview", newWin)
end

local function ensureNamespace()
    return api.nvim_create_namespace('fex')
end

local function ctxFromCurrent()
    local buf = api.nvim_get_current_buf()
    return {
        buf = buf,
        win = api.nvim_get_current_win(),
        ns = ensureNamespace(),
        options = api.nvim_buf_get_var(buf, "options"),
    }
end

local function setKeymaps(outerCtx)
    -- Preview utility function, set cmd to vs or sp
    local function preview(ctx, cmd)
        enter(ctx,
            -- Open file in preview window
            function(path)
                openPreview(ctx, cmd .. " " .. path,
                    function()
                    end)
            end,
            -- Open directory in preview window
            function(path)
                openPreview(ctx, cmd,
                    function()
                        M.open(path)
                    end)
            end)
    end

    keymaps = {
        {
            keys = "<CR>",
            desc = "Step into directory or open file in current window",
            func = function()
                enter(ctxFromCurrent(),
                    -- Open file in current window
                    function(path)
                        vim.cmd('e ' .. path)
                    end,
                    -- Open directory in current window
                    function(path)
                        open(ctxFromCurrent(), path)
                    end)
            end,
        },
        {
            keys = "v",
            desc = "Open preview of directory or file in vertical split window",
            func = function() preview(ctxFromCurrent(), "vs") end,
        },
        {
            keys = "s",
            desc = "Open preview of directory or file in split window",
            func = function() preview(ctxFromCurrent(), "sp") end,
        },
        {
            keys = "-",
            desc = "Step into parent directory",
            func = function()
                local ctx = ctxFromCurrent()
                local root = getRoot(ctx)
                local path = paths.full(root.name)
                local currDir = paths.directory(path)
                local parentDir = paths.directory(currDir)
                open(ctx, parentDir, paths.name(currDir))
            end,
        },
        {
            keys = "%",
            desc = "Create new file in current directory",
            func = function()
                local ctx = ctxFromCurrent()
                local curr = getCurrent(ctx)
                local name = vim.fn.input("New file:")
                if name == "" then
                    return
                end
                local path = paths.add(curr.root.name, name)
                vim.fn.writefile({}, path)
                open(ctx, curr.root.name, name)
            end,
        },
        {
            keys = "d",
            desc = "Create new directory in current directory",
            func = function()
                local ctx = ctxFromCurrent()
                local root = getRoot(ctx)
                local name = vim.fn.input("New directory:")
                if name == "" then
                    return
                end
                local path = paths.add(root.name, name)
                vim.fn.mkdir(path)
                open(ctx, root.name, name)
            end,
        },
        {
            keys = "D",
            desc = "Delete file or directory",
            func = function()
                local ctx = ctxFromCurrent()
                local curr = getCurrent(ctx)
                local flags = ""
                if curr.isDir then
                    flags = "d"
                end
                local choice = vim.fn.confirm("Delete " .. curr.fullPath, "&Yes\n&No")
                if choice == 1 then
                    vim.fn.delete(curr.fullPath, flags)
                    open(ctx, curr.root.name)
                end
            end,
        },
        {
            keys = "R",
            desc = "Rename file or directory",
            func = function()
                local ctx = ctxFromCurrent()
                local curr = getCurrent(ctx)
                local toPath = vim.fn.input("Rename " .. curr.fullPath .. " to:", curr.fullPath)
                if name == "" then
                    return
                end
                vim.fn.rename(curr.fullPath, toPath)
                -- TODO: If root changes we need to open something else..
                open(ctx, curr.root.name)
            end,
        }
    }
    for i = 1, #keymaps do
        m = keymaps[i]
        api.nvim_buf_set_keymap(outerCtx.buf, 'n', m.keys, '', {
            desc = m.desc,
            callback = m.func,
        })
    end
end

local function mergeOptions(defaults, overrides)
    if overrides == nil then
        return defaults
    end
    local options = {}
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
        path = paths.currentFile()
    else
        path = paths.full(path)
    end
    local directory = path
    local filename = paths.name(path)
    if filename then
        directory = paths.directory(path)
    end
    local ns  = ensureNamespace()
    -- Create a new buffer and attach it to the current window
    local buf = createBuffer(options)
    local win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
    local ctx = {
        buf = buf,
        win = win,
        ns = ns,
        options = options,
    }
    setKeymaps(ctx)
    open(ctx, directory, filename)
end

M.setup = function(options)
    globalOptions = mergeOptions(globalOptions, options)
end

return M
