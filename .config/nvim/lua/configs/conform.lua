local options = {
    formatters_by_ft = {
        lua = { "stylua" },
        c = { "clang-format" },
        cpp = { "clang-format" },
        python = { "isort", "black" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
    },

    formatters = {
        ["clang-format"] = {
            prepend_args = {
                "-style={ \
                IndentWidth: 4, \
                TabWidth: 4, \
                UseTab: Never, \
                AccessModifierOffset: 0, \
                IndentAccessModifiers: true, \
                PackConstructorInitializers: Never}",
            },
        },
        prettier = {
            prepend_args = {
                "--tab-width",
                "4",
            },
        },
        black = {
            prepend_args = {
                "--fast",
                "--line-length",
                "80",
            },
        },
        isort = {
            prepend_args = {
                "--profile",
                "black",
            },
        },
    },

    format_on_save = {
        -- These options will be passed to conform.format()
        timeout_ms = 1000,
        lsp_fallback = true,
    },
}

require("conform").setup(options)
