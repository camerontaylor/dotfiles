local ok, err = pcall(vim.treesitter.start)
if not ok then
  vim.notify("Treesitter parser missing: " .. err, vim.log.levels.WARN)
end
