local M = {}
local api = vim.api
local id = 0
local globalOptions = {
    ls = "-ahl --group-directories-first --time-style=\"long-iso\""
}
local render = require("render").render

local function createBuffer(options)
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    api.nvim_buf_set_option(buf, 'filetype', 'fex')
    api.nvim_buf_set_var(buf, "options", options)
    api.nvim_buf_set_var(buf, "preview", nil)
    return buf
end

local function trimTrailingSlash(path)
    -- Needs to remove the trailing slash if there is one
    if string.sub(path, #path, #path) == "/" then
        return string.sub(path, 1, #path - 1)
    end
    return path
end

local function findRoot(lines, line, delta)
    while line > 0 and line < (#lines + 1) do
        x = lines[line]
        if x.isRoot then
            return x
        end
        line = line + delta
    end
    print("not found")
end

local function getInfoFromLine(buf, ns, line)
    -- Retrieve lines meta data
    local lines = api.nvim_buf_get_var(buf, "lines")
    local entry = lines[line]
    local root = findRoot(lines, line, -1)
    return {
        root = root,
        entry = entry,
    }
end

local function openPath(ctx, path, optionalFilename)
    id = id + 1
    api.nvim_buf_set_name(ctx.buf, "fex " .. path .. " " .. id)
    local lines = render(ctx.win, ctx.buf, ctx.ns, ctx.options, path, optionalFilename)
    -- Store data about the parsed lines in buffer variable
    api.nvim_buf_set_var(ctx.buf, "lines", lines)
end

local function addToPath(path, toAdd)
    path = trimTrailingSlash(path)
    if toAdd == "." then
        return path
    end
    if toAdd == ".." then
        return vim.fn.fnamemodify(path, ":h")
    end
    return path .. "/" .. toAdd
end

local function enter(ctx, onFile, onDir)
    -- Find out the path that corresponds to the current line
    local pos = api.nvim_win_get_cursor(ctx.win)
    local line = pos[1]
    local info = getInfoFromLine(ctx.buf, ctx.ns, line)
    if info == nil then
        return
    end
    local path = addToPath(info.root.name, info.entry.name)
    if info.entry.isLink then
        path = info.entry.linkPath
    end
    if info.entry.isDir then
        onDir(path)
    else
        onFile(path)
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
                        openPath(ctxFromCurrent(), path)
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
                local lines = api.nvim_buf_get_var(ctx.buf, "lines")
                local root = findRoot(lines, 1, 1)
                local path = trimTrailingSlash(root.name)
                local name = vim.fn.fnamemodify(path, ":t")
                local parentPath = vim.fn.fnamemodify(path, ":h")
                openPath(ctx, parentPath, name)
            end,
        },
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
        path = vim.fn.expand("%:p")
    end
    local ftype = vim.fn.getftype(path)
    if ftype == nil then
        return
    end
    local filename = nil
    if ftype == "file" then
        -- Extract filename
        filename = vim.fn.fnamemodify(path, ":t")
    end
    -- Expand to full path
    path = vim.fn.fnamemodify(path, ":p:h")
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
    openPath(ctx, path, filename)
end

M.setup = function(options)
    globalOptions = mergeOptions(globalOptions, options)
end

return M
