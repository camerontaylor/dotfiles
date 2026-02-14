require('nvim-treesitter.config').setup({
  auto_install = true,
})


-- Auto-install parser then start treesitter for any filetype
vim.api.nvim_create_autocmd('FileType', {
  callback = function()
    local ok, _ = pcall(vim.treesitter.start)
    if not ok then
      -- Parser missing, trigger install and retry
      local lang = vim.treesitter.language.get_lang(vim.bo.filetype)
      if lang then
        pcall(vim.cmd, 'TSInstall ' .. lang)
      end
    end
  end,
})
