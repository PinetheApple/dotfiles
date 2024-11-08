vim.api.nvim_create_user_command("ToggleTransparency", function()
    require("base46").toggle_transparency()
end, {})
