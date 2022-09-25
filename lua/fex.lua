local M = {}
local api = vim.api
local statTypeTolsType = {
    dir = "FexDir",
    file = "FexFile",
    link = "FexLink",
}
local id = 0
local globalOptions = {
    lsArgs = "-ahl --group-directories-first --time-style=\"long-iso\""
}

local function onRoot(buf, parser, line, diredSize)
    -- Retrieve name without ending :
    name = string.sub(line, 1, #line - 1)
    table.insert(parser.lines, {type = "FexRoot", dired = diredSize, name = name, parent = 0, adjusted = -2})
    api.nvim_buf_set_lines(buf, -2, -2, false, {line})
    parser.line = parser.line + 1
    parser.state = 1
end

local function onTotal(buf, parser, line, diredSize)
    table.insert(parser.lines, {type = "FexTotal", dired = diredSize})
    api.nvim_buf_set_lines(buf, -2, -2, false, {line})
    parser.line = parser.line + 1
    parser.state = 2
end

local function onEmpty(buf, parser, diredSize)
    --  Enters new section
    parser.state = 0
    table.insert(parser.lines, {type = "FexBlank", dired = diredSize})
    api.nvim_buf_set_lines(buf, -2, -2, false, {""})
    parser.line = parser.line + 1
end

local function onDired(buf, parser, line)
    parser.state = 2
    sub = string.sub(line, 1, 8)
    if sub == "//DIRED-" then
        -- options
    elseif sub == "//DIRED/" then
        -- Offsets
        parser.diredOffsets = vim.split(line:gsub("//DIRED// ", ""), " ")
    end
end

local function onEntry(buf, parser, line, diredSize)
    -- Use first char to determine if this is a directory, file, link..
    prefix = string.sub(line, 1, 1)
    local type
    if prefix == "d" then
        type = "FexDir"
    elseif prefix == "l" then
        type = "FexLink"
    elseif prefix == "-" then
        type = "FexFile"
    end
    table.insert(parser.lines, {type = type, dired = diredSize})
    api.nvim_buf_set_lines(buf, -2, -2, false, {line})
    parser.line = parser.line + 1
    parser.state = 3
end

local function parseLine(buf, parser, line)
    if line == nil then
        return false
    end
    -- Keep note of the initial size of this for dired rendering
    local size = string.len(line) + 1 -- Plus one for newline
    -- Trim initial white space
    line = string.gsub(line, "^%s+", "")
    -- Root?
    if parser.state == 0 then
        -- Expecting either a total or a directory, in case of directory it ends with :
        if string.sub(line, #line, #line) == ":" then
            onRoot(buf, parser, line, size)
            return true
        end
    end
    -- Root or total?
    if parser.state == 0 or parser.state == 1 then
        if string.find(line, "total", 1, true) ~= nil then
            if parser.state == 0 then
                -- Add missing root
                onRoot(buf, parser, parser.root .. ":", 0)
                parser.parent = parser.line
            end
            -- Add total
            onTotal(buf, parser, line, size)
            return true
        end
        print("error")
        return false
    end
    -- Empty line?
    if line == "" then
        --  Enters new section
        onEmpty(buf, parser, size)
        return true
    end
    local prefix = string.sub(line, 1, 2)
    -- Dired data?
    if prefix == "//" then
        onDired(buf, parser, line)
        return true
    end
    -- Within directory listing
    onEntry(buf, parser, line, size)
    return true
end

local function render(ctx, path, selectName)
    local buf = ctx.buf
    local win = ctx.win
    local options = ctx.options
    local ns = ctx.ns
    api.nvim_buf_set_option(buf, 'modifiable', true)
    -- Clear existing lines
    api.nvim_buf_set_lines(buf, 0, -1, false, {})
    -- Clear highlights
    api.nvim_buf_clear_namespace(buf, -1, 0, -1)
    -- Invoke ls command and parse and render the result line by line
    -- The D option enables special dired output that is needed to avoid parsing filenames
    local lsCmd = "ls -D " .. options.lsArgs .. " " .. path
    local h = io.popen(lsCmd)
    local parser = { root = path, line = 0, lines = {}, state = 0 }
    while parseLine(buf, parser, h:read("*line")) do
    end
    -- Apply dired offsets to be able to locate and highlight names without
    -- having to bother about filename parsing
    local runningOffset = 0
    local diredOffsets = parser.diredOffsets
    local adjusted = 0
    local selectLine
    for k, v in pairs(parser.lines) do
        local hl = nil
        if v.type == "FexRoot" then
            adjusted = v.adjusted
            api.nvim_buf_set_extmark(buf, ns, k - 1, 0, {
                end_row = k - 1,
                end_col = #v.name,
                hl_group = "FexDir",
            })
        elseif v.type == "FexFile" then
            hl = v.type
        elseif v.type == "FexDir" then
            hl = v.type
        end
        if hl ~= nil then
            -- Pop start and stop from offsets
            local start = tonumber(table.remove(diredOffsets, 1)) - runningOffset + adjusted
            local stop = tonumber(table.remove(diredOffsets, 1)) - runningOffset + adjusted
            local name = api.nvim_buf_get_text(buf, k - 1, start, k - 1, stop, {})[1]
            -- Store the name in meta data
            v.name = name
            api.nvim_buf_set_extmark(buf, ns, k - 1, start, {
                end_row = k - 1,
                end_col = stop,
                hl_group = hl,
            })
            if selectName ~= nil then
                if name == selectName then
                    selectLine = k
                    selectName = nil
                end
            end
        end
        if v.dired > 0 then
            runningOffset = runningOffset + v.dired
        end
    end
    if selectLine then
        api.nvim_win_set_cursor(win, {selectLine, 0})
    end
    -- Store data about the parsed lines in buffer variable
    api.nvim_buf_set_var(buf, "lines", parser.lines)
    -- Make it read only
    api.nvim_buf_set_option(buf, 'modifiable', false)
end

local function createBuffer(options)
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    api.nvim_buf_set_option(buf, 'filetype', 'fex')
    api.nvim_buf_set_var(buf, "preview", nil)
    api.nvim_buf_set_var(buf, "lines", nil)
    api.nvim_buf_set_var(buf, "options", options)
    return buf
end

local function isDiredBuffer(buf)
    return true
end

local function getRootPath(buf)
    return api.nvim_buf_get_text(buf, 0, 0, 0, -1, {})[1]
end

local function findRoot(lines, line)
    while line > 0 do
        x = lines[line]
        if x.type == "FexRoot" then
            return x
        end
        line = line - 1
    end
    print("not found")
end

local function getInfoFromLine(buf, ns, line)
    -- Retrieve lines meta data
    local lines = api.nvim_buf_get_var(buf, "lines")
    local entry = lines[line]
    local root = findRoot(lines, line)
    return {
        root = root.name,
        name = entry.name,
        type = entry.type,
    }
end

local function openPath(ctx, path, optionalFilename)
    id = id + 1
    api.nvim_buf_set_name(ctx.buf, "fex " .. path .. " " .. id)
    render(ctx, path, optionalFilename)
end

local function getTypeFromFtype(path, options)
    local ftype = vim.fn.getftype(path)
    if ftype == nil then
        return nil
    end
    return statTypeTolsType[ftype]
end

local function enter(ctx, onFile, onDir)
    -- Find out the path that corresponds to the current line
    local pos = api.nvim_win_get_cursor(ctx.win)
    local line = pos[1]
    local info = getInfoFromLine(ctx.buf, ctx.ns, line)
    if info == nil then
        return
    end
    -- Check if it is a directory, file or link
    if info.type == "FexDir" then
        onDir(info)
    elseif info.type == "FexFile" then
        onFile(info)
    else
        --print("bad type")
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
            function(info)
                openPreview(ctx, cmd .. " " .. addToPath(info.root, info.name),
                    function()
                    end)
            end,
            -- Open directory in preview window
            function(info)
                openPreview(ctx, cmd,
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
                enter(ctxFromCurrent(),
                    -- Open file in current window
                    function(info)
                        vim.cmd('e ' .. addToPath(info.root, info.name))
                    end,
                    -- Open directory in current window
                    function(info)
                        openPath(ctxFromCurrent(), addToPath(info.root, info.name))
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
                local rootPath = getRootPath(ctx.buf)
                local name = vim.fn.fnamemodify(rootPath, ":t")
                local parentPath = vim.fn.fnamemodify(rootPath, ":h")
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
    local type = getTypeFromFtype(path, options)
    if type == nil then
        return
    end
    local filename = nil
    if type == "FexFile" then
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
