local M = {}

-- Will include a trailing /
M.full = function(path)
    return vim.fn.fnamemodify(path, ":p")
end

M.name = function(path)
    return vim.fn.fnamemodify(path, ":t")
end

M.directory = function(path)
    return vim.fn.fnamemodify(path, ":h")
end

-- Returns full expanded path to current file
M.currentFile = function()
    return vim.fn.expand("%:p")
end

M.add = function(path, part)
    path = vim.fn.fnamemodify(path, ":p")
    if part == "." then
        return path
    end
    if part == ".." then
        return M.directory(M.directory(path))
    end
    return path .. part
end

return M
