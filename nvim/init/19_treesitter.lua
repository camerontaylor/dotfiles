require('nvim-treesitter.config').setup({})

-- Start treesitter highlighting, installing the parser first if needed
vim.api.nvim_create_autocmd('FileType', {
  callback = function(ev)
    local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
    if not lang then return end

    if pcall(vim.treesitter.language.inspect, lang) then
      -- Parser already available, start immediately
      pcall(vim.treesitter.start, ev.buf)
    else
      -- Install parser then start treesitter for this buffer when done
      local buf = ev.buf
      require('nvim-treesitter.install').install({ lang }):await(function(err)
        if not err then
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(buf) then
              pcall(vim.treesitter.start, buf)
            end
          end)
        end
      end)
    end
  end,
})
