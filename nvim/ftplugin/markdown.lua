if vim.g.vscode then return end

vim.wo.spell = true
vim.wo.wrap = true

DotfilesTreesitter.attach({ indent = true, fold = true })
