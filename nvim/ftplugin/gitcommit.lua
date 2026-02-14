vim.wo.spell = true
vim.opt_local.sidescroll = 0
vim.opt_local.sidescrolloff = 0

vim.b.ministatusline_disable = true

pcall(vim.treesitter.start)

vim.cmd('startinsert')
