# Zero Home Presence Dotfiles

## License

[WTFPL](COPYING)

## There are many like it, but this one is mine

This repository contains tools and configurations I use in the shell. It
includes no graphical configurations, making it usable on servers and personal
workstations. It has been battle-tested on macOS and various Linux
distributions, including Debian, Ubuntu, CentOS, and even WSL.

I'm a big fan of the [XDG Base Directory
Specification](http://standards.freedesktop.org/basedir-spec/basedir-spec-latest.html)
and organize my dotfiles in a way that they don't clutter the `$HOME`
directory. I have reduced the files required in `$HOME` to a single
`.zshenv`; everything else goes under standard XDG paths or is launched via
aliases. Additionally, if you have root permissions, you can install dotfiles
with [zero home presence](#zero-home-presence).

## Features

* Extensive Zsh [configuration](zsh/rc.d) and [plugins](zsh/plugins), including:
  * [powerlevel10k](https://github.com/romkatv/powerlevel10k) prompt
  * [additional completions](https://github.com/zsh-users/zsh-completions)
  * [async autosuggestions plugin](https://github.com/zsh-users/zsh-autosuggestions)
  * [syntax highlighting plugin](https://github.com/zsh-users/zsh-syntax-highlighting)
  * [autoenv plugin](https://github.com/Tarrasch/zsh-autoenv)
  * [autopair plugin](https://github.com/hlissner/zsh-autopair)
  * [clean Zsh implementation of `z`](https://github.com/agkozak/zsh-z)
* Neovim [configuration](nvim/init.lua) and [plugins](nvim/plugins) (mini.nvim ecosystem; no plugin manager needed — plugins are git submodules under `nvim/plugins/`, loaded via Neovim's native `packpath`)
* Tmux [configuration](tmux/tmux.conf) and [plugins](tmux/plugins) including resurrect + continuum for session persistence across restarts
* Yazi [configuration](yazi/yazi.toml) and [plugins](yazi/plugins)
* Other configurations:
  * [ranger](configs/ranger)
  * [quilt](configs/quiltrc)
  * [Git](configs/gitconfig)
  * [htop](configs/htoprc)
  * [Ghostty](configs/ghostty)
* Handy [utilities](tools), including:
  * [fzf](https://github.com/junegunn/fzf)
  * [spark](https://github.com/holman/spark) to draw bar charts right in the console
  * [diff-so-fancy](https://github.com/so-fancy/diff-so-fancy) for a much better git diff layout
  * [git-extras](https://github.com/tj/git-extras) additional helpers for Git
* [mise](https://mise.jdx.dev/) for polyglot runtime/tool management — see
  [`configs/mise.toml`](configs/mise.toml). (Replaces the prior `*env` wrappers.)

## Installation

> [!NOTE]
> Vim configuration has been removed. Neovim is the only supported editor.
> If you need a fallback on a remote server without Neovim, install `nvim`
> via your package manager or use the `mise install` path here.

### Requirements

* `zsh` version 5.9 or newer is strongly recommended
* `git` all external components are added as git submodules

### Optional Dependencies

* `make` and `which` required to install git helpers
* `perl` diff-so-fancy runtime
* [`delta`](https://github.com/dandavison/delta) will be used as git pager instead of diff-so-fancy
* [`bat`](https://github.com/sharkdp/bat) will be used as man pager
* Nerd Fonts Symbols Only installed and enabled fallback in terminal emulator

### Location

Dotfiles can be installed in any directory, but probably somewhere under
`$HOME`. Personally, I use `$HOME/.local/dotfiles`. The installation is
simple:

```sh
git clone https://github.com/z0rc/dotfiles.git "$HOME/.local/dotfiles"
$HOME/.local/dotfiles/deploy.zsh
$HOME/.local/dotfiles/scripts/save-secrets.zsh      # optional, writes plaintext secret overrides back to .enc
$HOME/.local/dotfiles/scripts/restore-secrets.zsh  # optional, restores plaintext secrets
command -v brew >/dev/null 2>&1 && chsh -s "$(brew --prefix)/bin/zsh"  # macOS/Homebrew fallback
```

The [deployment script](deploy.zsh) sets up symlinks, installs git hooks,
runs `mise install`, and schedules a daily `git pull`. It dispatches into
[`scripts/deploy.d/NN_*.zsh`](scripts/deploy.d) fragments, each handling one
install concern (symlinks, submodules, brew, mise, sops, etc.). Shared
helpers live in [`scripts/deploy.d/lib/helpers.zsh`](scripts/deploy.d/lib/helpers.zsh).
The `scripts/post-merge` hook auto-re-runs deploy after every `git pull`
(with a `zsh -n` precheck and a 300s `timeout` cap; opt out per-pull with
`DOTFILES_SKIP_POSTMERGE=1`). Secret save/restore is separate and manual via
[`scripts/save-secrets.zsh`](scripts/save-secrets.zsh) and
[`scripts/restore-secrets.zsh`](scripts/restore-secrets.zsh). Managed SSH
files are stored as `ssh/*.enc` and restored to ignored plaintext files
under `ssh/`, which deploy symlinks into `~/.ssh/`.

`deploy.zsh` accepts:

| Flag | Meaning |
|------|---------|
| `--upgrade` / `-u` | run brew/mise/cargo upgrades in addition to installs |
| `--dry-run` / `-n` | fragments print intentions via `[dry-run]` without mutating |
| `--only NAME` | run only fragments whose basename matches NAME (e.g., `--only 30_submodules`); repeat for multiple |
| `--help` / `-h` | show flag summary |

### macOS Bootstrap (Day 0, before clone)

[`scripts/eris-macos-bootstrap.zsh`](scripts/eris-macos-bootstrap.zsh) is the
fresh-Mac entry point. It installs Homebrew + a baseline tool set (sops, age,
mise, caddy, etc.), then clones this repo and runs `deploy.zsh`. Since the
repo isn't cloned yet, fetch the script directly:

```sh
curl -fsSL https://raw.githubusercontent.com/z0rc/dotfiles/main/scripts/eris-macos-bootstrap.zsh -o ~/eris-macos-bootstrap.zsh
zsh ~/eris-macos-bootstrap.zsh
```

The script prints the manual System Settings grants (Full Disk Access, etc.)
needed before/after.

## Zero Home Presence

It's possible to install dotfiles without creating a `~/.zshenv` symlink. To
do so, set the environment variable `ZDOTDIR` to `<installation dir>/zsh`,
e.g., `$HOME/.local/dotfiles/zsh`. This variable should be set very early in
the login process, before zsh starts sourcing the user's `.zshenv`. One
possible option is to add:

```sh
export ZDOTDIR="$HOME/.local/dotfiles/zsh"
```

into `/etc/zsh/zshenv`. Alternatively, you can set it with a PAM environment
module.

## Neovim Version

Neovim configuration is tested with latest released Neovim version only. At the
moment of writing it's version 0.11.

## Configuration

### Git Configuration

Update `~/.config/git/local/user` with your email and name. It should look
like this:

```ini
[user]
    email = jdoe@example.com
    name = John Doe
```

You can also add additional configurations in `~/.config/git/local/stuff`.

### Zsh Configuration

Note that Zsh configuration skips every global configuration file except
`/etc/zsh/zshenv`.

You can add your local configuration into `$ZDOTDIR/env.d/9[0-9]_*` and
`$ZDOTDIR/rc.d/9[0-9]_*`. The difference is that `env.d` is sourced always,
while `rc.d` is sourced only in interactive sessions.

Additionally, `$ZDOTDIR/.zlogin` and `$ZDOTDIR/.zlogout` are available for
modifications, though they are missing by default.

### Neovim Configuration

Local configuration can be added to:

* `$DOTFILES/nvim/init/0[1-9]_*` (like `01_local.lua`) to load after default
  options, but before any plugin.
* `$DOTFILES/nvim/init/9[0-9]_*` (like `99_local.vim`) to load after plugins.

### Vim Configuration

Add your local configuration to `$DOTFILES/vim/vimrc.local`.

### Local Paths

Local binaries can be placed in `$HOME/.local/bin`; it's added to `PATH` by
default. Man pages can be placed in `$XDG_DATA_HOME/man`.

### Ignore Config Files Changes Locally

For example, Htop updates its config file `htoprc` when changing any view
mode or sort order. To ignore local changes to configuration files, you can do:

```sh
git update-index --assume-unchanged configs/htoprc
```

To restore git tracking of those files, use:

```sh
git update-index --no-assume-unchanged configs/htoprc
```
