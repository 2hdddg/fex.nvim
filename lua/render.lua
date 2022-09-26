local M = {}

local api = vim.api

local statTypeToType = {
    dir = "FexDir",
    file = "FexFile",
    link = "FexLink",
}

local function getTypeFromFtype(path)
    local ftype = vim.fn.getftype(path)
    if ftype == nil then
        return nil
    end
    return statTypeToType[ftype]
end
-- Export this as well
M.getTypeFromFtype = getTypeFromFtype

local function insertLine(buf, parser, line, meta)
    table.insert(parser.lines, meta)
    api.nvim_buf_set_lines(buf, -2, -2, false, {line})
end

local function onRoot(buf, parser, line, diredSize)
    -- Retrieve name without ending :
    local name = string.sub(line, 1, #line - 1)
    insertLine(buf, parser, line, {type = "FexRoot", dired = diredSize, name = name, adjusted = -2})
    parser.state = 1
end

local function onTotal(buf, parser, line, diredSize)
    insertLine(buf, parser, line, {type = "FexTotal", dired = diredSize})
    parser.state = 2
end

local function onEmpty(buf, parser, diredSize)
    insertLine(buf, parser, "", {type = "FexBlank", dired = diredSize})
    parser.state = 0 --  Enters new section
end

local function onDired(buf, parser, line)
    parser.state = 2
    local sub = string.sub(line, 1, 8)
    if sub == "//DIRED/" then
        -- Offsets
        parser.diredOffsets = vim.split(line:gsub("//DIRED// ", ""), " ")
    end
    -- Don't care about DIRED-OPTIONS or SUBDIRED at this point
end

local function onEntry(buf, parser, line, diredSize)
    -- Use first char to determine if this is a directory, file, link..
    local type
    local prefix = string.sub(line, 1, 1)
    if prefix == "d" then
        type = "FexDir"
    elseif prefix == "l" then
        type = "FexLink"
    elseif prefix == "-" then
        type = "FexFile"
    end
    insertLine(buf, parser, line, {type = type, dired = diredSize})
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

M.render = function(win, buf, ns, options, path, selectName)
    api.nvim_buf_set_option(buf, 'modifiable', true)
    -- Clear existing lines
    api.nvim_buf_set_lines(buf, 0, -1, false, {})
    -- Clear highlights
    api.nvim_buf_clear_namespace(buf, -1, 0, -1)
    -- Invoke ls command and parse and render the result line by line
    -- The D option enables special dired output that is needed to avoid parsing filenames
    local lsCmd = "ls -D " .. options.ls .. " " .. path
    local h = io.popen(lsCmd)
    local parser = { root = path, lines = {}, state = 0 }
    while parseLine(buf, parser, h:read("*line")) do
    end
    -- Apply dired offsets to be able to locate and highlight names without
    -- having to bother about filename parsing
    local runningOffset = 0
    local diredOffsets = parser.diredOffsets
    local adjusted = 0
    local selectLine
    local selectColumn
    for k, v in pairs(parser.lines) do
        local hl = nil
        if v.type == "FexRoot" then
            adjusted = v.adjusted
            api.nvim_buf_set_extmark(buf, ns, k - 1, 0, {
                end_row = k - 1,
                end_col = #v.name,
                hl_group = "FexDir",
            })
        elseif v.type == "FexBlank" or v.type == "FexTotal" then
        else
            hl = v.type
        end
        if hl ~= nil then
            -- Pop start and stop from offsets
            local start = tonumber(table.remove(diredOffsets, 1)) - runningOffset + adjusted
            local stop = tonumber(table.remove(diredOffsets, 1)) - runningOffset + adjusted
            local name = api.nvim_buf_get_text(buf, k - 1, start, k - 1, stop, {})[1]
            -- Store the name in meta data
            v.name = name
            if v.type == "FexLink" then
                -- Also store the link path
                local linkPath = api.nvim_buf_get_text(buf, k - 1, stop + 4, k - 1, -1, {})[1]
                v.linkPath = linkPath
                -- Check type of the link
                v.linkType = getTypeFromFtype(linkPath)
                hl = v.linkType
            end
            api.nvim_buf_set_extmark(buf, ns, k - 1, start, {
                end_row = k - 1,
                end_col = stop,
                hl_group = hl,
            })
            if selectLine == nil then
                selectLine = k
                selectColumn = start
            end
            if selectName ~= nil then
                if name == selectName then
                    selectLine = k
                    selectColumn = start
                    selectName = nil
                end
            end
        end
        if v.dired > 0 then
            runningOffset = runningOffset + v.dired
        end
    end
    if selectLine then
        api.nvim_win_set_cursor(win, {selectLine, selectColumn})
    end
    -- Make it read only
    api.nvim_buf_set_option(buf, 'modifiable', false)
    -- Someone probably needs to keep track of these
    return parser.lines
end

return M
