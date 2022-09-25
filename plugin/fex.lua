if vim.g.loaded_fex == 1 then
    return
end
vim.g.loaded_fex = 1

-- Register highlights
local highlights = {
    FexDir = { default = true, link = "netrwDir" },
    FexFile = { default = true, link = "netrwExe" },
}
for k, v in pairs(highlights) do
  vim.api.nvim_set_hl(0, k, v)
end

-- Register user command
vim.api.nvim_create_user_command("Fex", function(opts)
    require("fex").open()
end, {
    nargs = "*",
    complete = function(_, line)
        -- Auto complete
    end,
})
