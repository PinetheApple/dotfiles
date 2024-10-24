local options = {
    ensure_installed = {
        "vim",
        "lua",
        "html",
        "css",
        "rust",
        "python",
        "javascript",
        "bash",
        "powershell",
        "c",
        "cpp",
    },

    highlight = {
        enable = true,
        use_languagetree = true,
    },

    indent = { enable = true },
}

require("nvim-treesitter.configs").setup(options)
