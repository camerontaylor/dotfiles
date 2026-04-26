-- Minimal nvim init for vscode-neovim extension.
-- Loaded ONLY when running under VSCode (vim.g.vscode == 1).
-- No plugins, no UI — VSCode owns rendering, LSP, git, tree, statusline, etc.
-- Point the extension here via vscode-neovim.neovimInitVimPaths.linux in settings.json.

vim.loader.enable()

-- Verification marker. In a VSCode buffer, press `:` then type:
--   lua =vim.g.init_vscode_loaded
-- Should echo 1. If it echoes nil, the extension is NOT using this init.
vim.g.init_vscode_loaded = 1

-- options: editing behavior only
vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.tabstop = 4
vim.o.softtabstop = 4
vim.o.autoindent = true
vim.o.scrolloff = 8
vim.o.sidescrolloff = 8
vim.o.confirm = true
vim.o.iskeyword = '@,48-57,_,192-255,-'
vim.o.ttimeoutlen = 0
vim.o.ignorecase = true
vim.o.smartcase = true

-- secondary keyboard layout (kept from main config)
vim.o.keymap = 'ukrainian-enhanced'
vim.o.iminsert = 0
vim.o.imsearch = 0

-- clipboard: system + OSC52 fallback over SSH
vim.schedule(function()
  vim.o.clipboard = 'unnamedplus'
  if vim.env.SSH_TTY then vim.g.clipboard = 'osc52' end
end)

-- speed up startup: disable unused providers + netrw
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- silence nvim LSP log (VSCode handles diagnostics)
vim.lsp.log.set_level(vim.log.levels.OFF)

-- keymaps: only the ones that make sense inside VSCode buffers

-- send c/d to register "a so they don't clobber the clipboard
vim.keymap.set({ 'n', 'x' }, 'c', '"ac')
vim.keymap.set({ 'n', 'x' }, 'd', '"ad')

-- visual shifting keeps selection
vim.keymap.set('v', '<', '<gv')
vim.keymap.set('v', '>', '>gv')

-- cmdline sanity: wildmenu-aware arrows
-- https://github.com/neovim/neovim/issues/9953#issuecomment-1732700161
local cmap = function(lhs, rhs) vim.keymap.set('c', lhs, rhs, { expr = true }) end
cmap('<Up>',    function() return vim.fn.wildmenumode() == 1 and '<Left>'  or '<Up>'    end)
cmap('<Down>',  function() return vim.fn.wildmenumode() == 1 and '<Right>' or '<Down>'  end)
cmap('<Left>',  function() return vim.fn.wildmenumode() == 1 and '<Up>'    or '<Left>'  end)
cmap('<Right>', function() return vim.fn.wildmenumode() == 1 and '<Down>'  or '<Right>' end)
