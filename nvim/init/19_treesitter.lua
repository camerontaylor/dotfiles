require('nvim-treesitter.config').setup({})

-- Treesitter is enabled again, but missing parsers are installed in the
-- background so opening a new filetype does not block the UI.
if vim.g.dotfiles_treesitter_enabled == nil then
  vim.g.dotfiles_treesitter_enabled = true
end

DotfilesTreesitter = {}

local install_inflight = {}
local install_failed = {}
local install_prereqs_warned = false

local function dotfiles_treesitter_current_lang(buf)
  local filetype = vim.bo[buf or 0].filetype
  if filetype == '' then
    return
  end

  return vim.treesitter.language.get_lang(filetype)
end

function DotfilesTreesitter.is_enabled()
  return vim.g.dotfiles_treesitter_enabled == true
end

function DotfilesTreesitter.has_parser(buf)
  if not DotfilesTreesitter.is_enabled() then
    return false
  end

  local lang = dotfiles_treesitter_current_lang(buf)
  if not lang then
    return false
  end

  return pcall(vim.treesitter.language.inspect, lang)
end

function DotfilesTreesitter.ensure_parser(buf)
  if not DotfilesTreesitter.is_enabled() then
    return false
  end

  local lang = dotfiles_treesitter_current_lang(buf)
  if not lang then
    return false
  end

  if DotfilesTreesitter.has_parser(buf) then
    return true
  end

  if vim.fn.executable('tree-sitter') ~= 1 then
    if not install_prereqs_warned then
      install_prereqs_warned = true
      vim.schedule(function()
        vim.notify(
          'Treesitter auto-install needs the tree-sitter CLI; existing parsers still work, but new ones will not auto-install until that tool is available.',
          vim.log.levels.WARN
        )
      end)
    end
    return false
  end

  if install_inflight[lang] or install_failed[lang] then
    return false
  end

  install_inflight[lang] = true
  require('nvim-treesitter.install').install({ lang }):await(function(err, ok)
    install_inflight[lang] = nil

    vim.schedule(function()
      if err or ok == false then
        install_failed[lang] = true
        vim.notify(
          ('Treesitter parser install failed for %s; not retrying automatically this session.'):format(lang),
          vim.log.levels.WARN
        )
        return
      end

      install_failed[lang] = nil
      vim.notify(
        ('Treesitter parser installed for %s; it will be used for new buffers.'):format(lang),
        vim.log.levels.INFO
      )
    end)
  end)

  return false
end

function DotfilesTreesitter.attach(opts)
  opts = opts or {}

  if not DotfilesTreesitter.has_parser(0) then
    DotfilesTreesitter.ensure_parser(0)
    return false
  end

  pcall(vim.treesitter.start)

  if opts.indent then
    vim.bo.indentexpr = 'v:lua.DotfilesTreesitter.indentexpr()'
  end

  if opts.fold then
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = 'v:lua.DotfilesTreesitter.foldexpr()'
  end

  return true
end

function DotfilesTreesitter.indentexpr()
  if not DotfilesTreesitter.has_parser(0) then
    return -1
  end

  return require('nvim-treesitter').indentexpr()
end

function DotfilesTreesitter.foldexpr()
  if not DotfilesTreesitter.has_parser(0) then
    return '0'
  end

  return vim.treesitter.foldexpr()
end
