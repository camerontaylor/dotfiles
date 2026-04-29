if vim.g.vscode then return end

vim.bo.expandtab = false

DotfilesTreesitter.attach({ fold = true })
