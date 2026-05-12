if vim.g.vscode then return end

vim.bo.bufhidden = 'unload'
vim.wo.sidescrolloff = 0

vim.cmd.wincmd('L')
vim.cmd('vertical resize 79')

DotfilesTreesitter.attach()
