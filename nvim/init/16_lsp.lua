if vim.g.vscode then return end

---@diagnostic disable-next-line: missing-fields
require('lazydev').setup({
  library = {
    { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
  },
})

-- Armed FALSE before setup() so a failed require/launch can never inherit a
-- stale true; scripts/tests/nvim-load-probe.sh asserts
-- vim.g.blink_cmp_configured, which 16_lsp.lua sets true immediately after
-- setup() returns below.
vim.g.blink_cmp_configured = false
require('blink.cmp').setup({
  cmdline = {
    enabled = false,
  },
  sources = {
    default = { 'lsp', 'path', 'buffer', 'snippets' },
    per_filetype = {
      codecompanion = { 'codecompanion' },
      lua = { inherit_defaults = true, 'lazydev' },
    },
    providers = {
      lazydev = {
        name = 'LazyDev',
        module = 'lazydev.integrations.blink',
        score_offset = 100,
      },
    },
  },
  keymap = {
    preset = 'enter',
  },
  fuzzy = {
    implementation = 'lua',
  },
  completion = {
    menu = {
      draw = {
        treesitter = { 'lsp' },
      },
    },
    list = {
      selection = {
        preselect = false,
      },
    },
    documentation = {
      auto_show = true,
    },
    trigger = {
      prefetch_on_insert = false,
    },
  },
  signature = {
    enabled = true,
    window = {
      show_documentation = false,
    },
  },
})

-- setup() RETURNED: mark configured so scripts/tests/nvim-load-probe.sh
-- asserts reality, not intent. Placement is load-bearing — before setup()
-- the flag is a lie on every broken startup; after it, only a successful
-- require + configure can set it.
vim.g.blink_cmp_configured = true

require('mason').setup()
require('mason-lspconfig').setup()

require('conform').setup({
  formatters_by_ft = {
    lua = { 'stylua' },
    terraform = { 'terraform_fmt' },
  },
  format_on_save = {
    timeout_ms = 500,
    lsp_format = 'fallback',
  },
})
