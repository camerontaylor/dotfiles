# Karabiner-Elements config generation (macOS only).
#
# The single source of truth is the typed generator configs/karabiner/karabiner.ts.
# Karabiner-Elements itself OWNS the live ~/.config/karabiner/karabiner.json: it
# rewrites that file from its GUI and injects machine-specific device state
# (per-keyboard identifiers) we do NOT want symlinked into the repo and bled
# across the iMac Pro / Mac Studio pair. So rather than symlink it (the way
# 20_symlinks.zsh handles the static aerospace.toml), we GENERATE a real file
# here and leave Karabiner free to manage it afterwards. The generated JSON is a
# build artifact, so it is deliberately NOT committed — only karabiner.ts is.
#
# Regeneration is gated on the generator being newer than the installed config
# (or the config being absent), so GUI tweaks made between deploys are not
# clobbered every run — edit karabiner.ts to push a curated change and the next
# deploy picks it up. The generator backs up any existing target to .bak and
# honours $XDG_CONFIG_HOME.

if [[ $DOTFILES_OS != Darwin ]]; then
    return 0
fi

local kb_src=$SCRIPT_DIR/configs/karabiner/karabiner.ts
local kb_target=$XDG_CONFIG_HOME/karabiner/karabiner.json

zf_mkdir -p $XDG_CONFIG_HOME/karabiner

if [[ -e $kb_target && ! $kb_src -nt $kb_target ]]; then
    printf '%s\n' "Karabiner config up to date (karabiner.ts not newer); skipping"
    return 0
fi

printf '%s\n' "Generating Karabiner config from karabiner.ts..."

# bun executes TypeScript directly and is installed by mise (50_mise.zsh, which
# runs before this fragment); tsx / `npx tsx` cover any host without it.
local kb_runner=
local r
for r in bun tsx; do
    if have "$r"; then
        kb_runner=$r
        break
    fi
done
if [[ -z $kb_runner ]] && have npx; then
    kb_runner='npx --yes tsx'
fi

if [[ -z $kb_runner ]]; then
    printf '%s\n' "  ...no TypeScript runtime (bun/tsx/npx) on PATH; install one, then"
    printf '%s\n' "     re-run: bun ${(D)kb_src}"
    return 0
fi

# The generator writes $XDG_CONFIG_HOME/karabiner/karabiner.json and creates its
# own .bak, so a successful run leaves the target in place; Karabiner hot-reloads.
if eval "$kb_runner ${(q)kb_src}" > /dev/null 2>&1; then
    printf '%s\n' "  ...generated via $kb_runner"
else
    printf '%s\n' "  ...failed to generate Karabiner config (run 'bun ${(D)kb_src}' to see the error)"
fi
