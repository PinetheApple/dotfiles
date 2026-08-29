require("nvchad.mappings")

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })

-- terminal
map({ "n", "t", "i", "v" }, "<C-`>", function()
    require("nvchad.term").toggle({ pos = "sp", id = "htoggleTerm" })
end, { desc = "toggle horizontal terminal" })

-- comments
map("n", "<C-/>", "gcc", { desc = "toggle comment", remap = true })
map("v", "<C-/>", "gc", { desc = "toggle comment", remap = true })

-- tabufline
map("n", "<C-x>", function()
    require("nvchad.tabufline").close_buffer()
end, { desc = "buffer close" })
