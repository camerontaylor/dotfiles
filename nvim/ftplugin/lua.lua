if vim.g.vscode then return end

vim.bo.tabstop = 2
vim.bo.softtabstop = 2
vim.bo.shiftwidth = 2

DotfilesTreesitter.attach({ indent = true, fold = true })
