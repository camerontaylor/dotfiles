if vim.g.vscode then return end

vim.bo.textwidth = 79

DotfilesTreesitter.attach({ indent = true, fold = true })
