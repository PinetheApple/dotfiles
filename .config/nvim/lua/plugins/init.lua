return {
  {
    "stevearc/conform.nvim",
    event = 'BufWritePre', -- format on save
    config = function ()
      require "configs.conform"
    end,
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require("nvchad.configs.lspconfig").defaults()
      require "configs.lspconfig"
    end,
  },

  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "bashls",
        "lua_ls",
        "ast_grep",
        "rust_analyzer",
        "powershell_es",
      }
    }
  },

  {
    "nvim-treesitter/nvim-treesitter",
  	opts = {
  		ensure_installed = {
  			"vim",
        "lua",
        "vimdoc",
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
  	},
  },
}
