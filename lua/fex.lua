local M = {}
local api = vim.api
local id = 0
local globalOptions = {
    ls = "-Ahl --group-directories-first --time-style=\"long-iso\"",
    toggleBackFromTerminal = "<C-z>",
}
local render = require("render").render
local paths = require("paths")

local function createBuffer(options)
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, "buftype", "nofile")
    api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    api.nvim_buf_set_option(buf, "filetype", "fex")
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

local function show(ctx, path, optionalFilename)
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
    elseif curr.isFile or curr.isDir then
        curr.fullPath = paths.add(curr.root.name, curr.name)
    end
    return curr
end

local function view(ctx, onFile, onDir)
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

-- Preview utility function, set cmd to vs or sp
local function preview(ctx, cmd)
    local function maintainWindows(ctx, cmd, inNewWindow)
        closePreview(ctx.buf)
        vim.cmd(cmd)
        local newWin = api.nvim_get_current_win()
        inNewWindow()
        -- Keep focus in file explorer
        api.nvim_set_current_win(ctx.win)
        api.nvim_buf_set_var(ctx.buf, "preview", newWin)
    end

    view(ctx,
        -- Open file in preview window
        function(path)
            maintainWindows(ctx, cmd .. " " .. path,
                function()
                end)
        end,
        -- Open directory in preview window
        function(path)
            maintainWindows(ctx, cmd,
                function()
                    M.open(path)
                end)
        end)
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

M.view = function()
    view(ctxFromCurrent(),
        -- Open file in current window
        function(path)
            vim.cmd('e ' .. path)
        end,
        -- Open directory in current window
        function(path)
            show(ctxFromCurrent(), path)
        end)
end

M.viewParent = function()
    local ctx = ctxFromCurrent()
    local root = getRoot(ctx)
    local path = paths.full(root.name)
    local currDir = paths.directory(path)
    local parentDir = paths.directory(currDir)
    show(ctx, parentDir, paths.name(currDir))
end

M.previewSp = function()
    preview(ctxFromCurrent(), "sp")
end

M.previewVs = function()
    preview(ctxFromCurrent(), "vs")
end

M.createDirectory = function()
    local ctx = ctxFromCurrent()
    local root = getRoot(ctx)
    local name = vim.fn.input("New directory:")
    if name == "" then
        return
    end
    local path = paths.add(root.name, name)
    vim.fn.mkdir(path)
    show(ctx, root.name, name)
end

M.createFile = function()
    local ctx = ctxFromCurrent()
    local curr = getCurrent(ctx)
    local name = vim.fn.input("New file:")
    if name == "" then
        return
    end
    local path = paths.add(curr.root.name, name)
    vim.fn.writefile({}, path)
    show(ctx, curr.root.name, name)
end

M.delete = function()
    local ctx = ctxFromCurrent()
    local curr = getCurrent(ctx)
    local flags
    if curr.isDir then
        flags = "d"
    elseif curr.isFile then
        flags = ""
    else
        return
    end
    local choice = vim.fn.confirm("Delete " .. curr.fullPath, "&Yes\n&No")
    if choice == 1 then
        vim.fn.delete(curr.fullPath, flags)
        show(ctx, curr.root.name)
    end
end

M.rename = function()
    local ctx = ctxFromCurrent()
    local curr = getCurrent(ctx)
    if not (curr.isDir or curr.isFile) then
        return
    end
    local toPath = vim.fn.input("Rename " .. curr.fullPath .. " to:", curr.fullPath)
    if name == "" then
        return
    end
    vim.fn.rename(curr.fullPath, toPath)
    -- TODO: If root changes we need to open something else..
    show(ctx, curr.root.name)
end

M.yankPath = function()
    local curr = getCurrent(ctxFromCurrent())
    vim.fn.setreg(vim.v.register, curr.fullPath, "l")
end

M.terminalHere = function()
    local ctx = ctxFromCurrent()
    local curr = getCurrent(ctx)
    local path
    if curr.isFile then
        path = curr.root.name
    elseif curr.isDir then
        path = curr.fullPath
    else
        return
    end

    -- Create new listed buf. List it so that any running jobs in the terminal
    -- isn't lost to the user.
    local terminalBuf = api.nvim_create_buf(true, true)
    -- Switch to showing the new buffer. This will erase the current fex buffer.
    vim.api.nvim_win_set_buf(ctx.win, terminalBuf)
    local chanId = vim.fn.termopen("/bin/bash", {cwd = path})
    if chanId == 0 or chanId == -1 then
        return
    end
    local function toggleBack()
        -- Executing in terminal buffer. Reopen the explorer but terminate
        -- any jobs running in the terminal first. Should perhaps be a way
        -- to notify user about this... Best way would be to be able to detect
        -- any running jobs in the shell and prevent toggling back when something
        -- is running.
        vim.fn.jobstop(chanId)
        vim.fn.jobwait({chanId}, 1000)
        api.nvim_buf_set_option(terminalBuf, "bufhidden", "wipe")
        M.open(path, ctx.options)
    end
    api.nvim_buf_set_keymap(terminalBuf, 'n', ctx.options.toggleBackFromTerminal, '', {
        noremap = true,
        callback = toggleBack,
    })
    api.nvim_buf_set_keymap(terminalBuf, 't', ctx.options.toggleBackFromTerminal, '', {
        noremap = true,
        callback = toggleBack,
    })
    vim.cmd("startinsert")
end

local function setKeymaps(ctx, keymaps)
    for i = 1, #keymaps do
        m = keymaps[i]
        api.nvim_buf_set_keymap(ctx.buf, 'n', m.keys, '', {
            desc = m.desc,
            callback = m.func,
        })
    end
end

local function merge(defaults, overrides)
    if overrides == nil then
        return defaults
    end
    local options = {}
    for k, v in pairs(defaults) do
        if overrides[k] then
            if type(v) == "table" then
                options[k] = merge(v, overrides[k])
            else
                options[k] = overrides[k]
            end
        else
            options[k] = v
        end
    end
    return options
end

M.open = function(path, options)
    options = merge(globalOptions, options)
    if path == nil then
        path = paths.currentFile()
    else
        path = paths.full(path)
    end
    -- Make sure that path exists
    local ftype = vim.fn.getftype(path)
    if ftype == "" then
        path = vim.fn.getcwd() .. "/"
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
    local keymaps = {
        {
            keys = "<CR>",
            desc = "Step into directory or open file in current window",
            func = M.view,
        },
        {
            keys = "v",
            desc = "Open preview of directory or file in vertical split window",
            func = M.previewVs,
        },
        {
            keys = "s",
            desc = "Open preview of directory or file in split window",
            func = M.previewSp,
        },
        {
            keys = "-",
            desc = "Step into parent directory",
            func = M.viewParent,
        },
        {
            keys = "%",
            desc = "Create new file in current directory",
            func = M.createFile,
        },
        {
            keys = "d",
            desc = "Create new directory in current directory",
            func = M.createDirectory,
        },
        {
            keys = "D",
            desc = "Delete file or directory",
            func = M.delete,
        },
        {
            keys = "R",
            desc = "Rename file or directory",
            func = M.rename,
        },
        {
            keys = "Y",
            desc = "Yank full path to file or directory",
            func = M.yankPath,
        },
        {
            keys = "<C-z>",
            desc = "Terminal here",
            func = M.terminalHere,
        },
    }
    setKeymaps(ctx, keymaps)
    show(ctx, directory, filename)
end

M.setup = function(options)
    globalOptions = merge(globalOptions, options)
end

return M
