if vim.g.loaded_fex == 1 then
    return
end
vim.g.loaded_fex = 1

-- Register highlights

-- Register user command
vim.api.nvim_create_user_command("Fex", function(opts)
    require("fex").open()
end, {
    nargs = "*",
    complete = function(_, line)
        -- Auto complete
    end,
})
