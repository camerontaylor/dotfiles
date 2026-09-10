# offload-home: neptune keeps the Unix-side of $HOME on the external offload
# volume (WD SN810 over Thunderbolt), with compatibility symlinks from $HOME.
# ~/Library and the macOS canonical folders (Desktop/Documents/Downloads/...)
# stay on the internal disk — only the dotdirs a Linux box would recognize
# move. Design rationale, risk register, and the migration runbook live in
# docs/offload-home.md.
#
# Activated ONLY on the macOS host whose short hostname is "neptune" (extend
# the hostname check if another always-on desktop joins the scheme — never a
# laptop: a drive absent at login breaks every agent under ~/.local). This
# fragment DECLARES, verifies, and drift-corrects the symlink farm; the
# ditto/rsync+swap migration itself stays human-run (data movement on live
# dirs, eyes on — same principle as the repo's root steps).
#
# WHY 08, ahead of 10_dirs: both drivers run err_exit, and `mkdir -p` through
# a dangling symlink exits 1 — so once rows have migrated, an absent volume
# would kill the deploy inside 10_dirs with a bare "No such file or
# directory". At 08 the same state either skips cleanly (nothing migrated
# yet) or fails fast naming the dangling rows and the fix.

if [[ $DOTFILES_OS != Darwin ]]; then
    return 0
fi

self=
self=$(scutil --get LocalHostName 2>/dev/null) || self=$(hostname -s 2>/dev/null) || self=""
if [[ -z $self ]]; then
    printf '%s\n' "offload-home: could not determine local hostname, skipping"
    return 0
fi
if [[ $self != neptune ]]; then
    return 0
fi

offload_vol=/Volumes/offload
offload_root=$offload_vol/neptune

printf '%s\n' "Checking offload-home links on $self..."

# src|dst[|flags] rows (the repo's manifest convention): $HOME/<src> is a
# compatibility symlink pointing at <dst>. <dst> is canonical FOREVER —
# pnpm/uv/venvs bake absolute paths and node realpaths aggressively, so a link
# is created once and never re-pointed (docs/offload-home.md, Invariants).
#   nocopy — the $HOME side holds nothing worth copying (caches): the printed
#            migration discards the volume side and links a fresh dir.
#   regen  — regenerable: the soak fallback may be deleted after one good
#            tool run, not held for the full soak window.
# Adding a directory to the farm = adding a row here, nothing else. `repos`
# and `.npm` predate this fragment (hand-migrated); declaring them here puts
# them under verification and drift correction from now on.
offload_rows=(
    'repos|/Volumes/offload/neptune/repos'
    '.npm|/Volumes/offload/neptune/.npm'
    '.local|/Volumes/offload/neptune/.local'
    '.cache|/Volumes/offload/neptune/.cache|nocopy,regen'
    '.config|/Volumes/offload/neptune/.config'
    '.vscode|/Volumes/offload/neptune/.vscode|regen'
    '.colima|/Volumes/offload/neptune/.colima'
    '.gradle|/Volumes/offload/neptune/.gradle|regen'
    '.rustup|/Volumes/offload/neptune/.rustup|regen'
    '.cargo|/Volumes/offload/neptune/.cargo|regen'
)

# Volume absent. Inert before any row migrates (skip with a note); fatal once
# farm links dangle — from 10_dirs.zsh on, every fragment writes through $HOME
# paths that resolve into the volume. Enumerate ALL dangling rows, then stop
# the deploy here with the fix, instead of letting 10_dirs die cryptically.
if [[ ! -d $offload_root ]]; then
    if [[ -d $offload_vol ]]; then
        _why="$offload_vol is mounted but $offload_root is missing"
    else
        _why="$offload_vol is not mounted"
    fi
    _dangling=()
    for _row in "${offload_rows[@]}"; do
        _name=${_row%%|*}
        if [[ -L $HOME/$_name && ! -e $HOME/$_name ]]; then
            _dangling+=("~/$_name")
        fi
    done
    if (( ${#_dangling[@]} > 0 )); then
        printf '%s\n' "  ...FATAL: $_why, and farm links dangle: ${_dangling[*]}"
        printf '%s\n' "        Plug the enclosure back in / remount, then re-run. Until then"
        printf '%s\n' "        every path through those links is dead (docs/offload-home.md)"
        return 1
    fi
    printf '%s\n' "  ...$_why, no dangling farm links — skipping (docs/offload-home.md)"
    return 0
fi

# Ownership must be enabled on the volume. With "Owners: Disabled" APFS mounts
# noowners: mode bits turn advisory (chmod 600 stops meaning anything) and
# chown fails — untenable for a volume holding ~/.config/gnupg and 20G of
# mise toolchains behind ~/.local/share/mise/shims. Plain grep (not -q) so the
# producer is drained and cannot SIGPIPE under pipefail; || true tolerates a
# missing line.
_owners=
_owners=$(diskutil info $offload_vol 2>/dev/null | grep '^ *Owners:' || true)
case $_owners in
    *Enabled*) ;;
    *) printf '%s\n' "  ...WARNING: ownership DISABLED on $offload_vol — mode bits are advisory there. Fix: sudo diskutil enableOwnership $offload_vol" ;;
esac

# Walk the rows. `nocopy` rows never classify as CONFLICT: their volume side
# is declared disposable, so an existing dst is garbage to clear, not a
# both-sides-have-real-data situation.
_row= _name= _rest= _dst= _flags= _home_path= _link=
_ok=0 _pending=0 _fixed=0 _broken=0 _conflict=0
for _row in "${offload_rows[@]}"; do
    _name=${_row%%|*}
    _rest=${_row#*|}
    _dst=${_rest%%|*}
    case $_rest in
        *'|'*) _flags=${_rest#*|} ;;
        *) _flags= ;;
    esac
    _home_path=$HOME/$_name
    if [[ -L $_home_path ]]; then
        _link=$(readlink "$_home_path")
        if [[ ! -e $_dst ]]; then
            # Half-migrated row or a stale volume. Never auto-fix by pointing
            # somewhere else — the target is canonical, so a missing target
            # means the data is missing. Counted here; fatal after the summary
            # so every row gets its say first.
            printf '%s\n' "  ...BROKEN: ~/$_name -> $_link but $_dst is missing — investigate (docs/offload-home.md)"
            _broken=$((_broken+1))
        elif [[ $_link == "$_dst" ]]; then
            _ok=$((_ok+1))
        else
            printf '%s\n' "  ...drift: repointing ~/$_name (was: $_link)"
            deploy_ln -sfn "$_dst" "$_home_path"
            _fixed=$((_fixed+1))
        fi
    elif [[ -e $_home_path ]]; then
        if [[ -e $_dst ]] && [[ $_flags != *nocopy* ]]; then
            printf '%s\n' "  ...CONFLICT: ~/$_name is a real dir AND $_dst exists — resolve by hand:"
            printf '%s\n' "        rsync -aHAXn --delete --itemize-changes $_home_path/ $_dst/ | head"
            _conflict=$((_conflict+1))
        else
            # Pre-migration nag. The exact commands are printed from the same
            # rows that define the farm, so the runbook can never drift from
            # the manifest. Copy rows are two-pass: bulk ditto while live,
            # then after quiescing the row (runbook) catch up the delta and
            # swap. NOT `diff -rq`: it follows symlinks and exits 2 on the
            # deliberately-dangling links 20_symlinks.zsh leaves in ~/.config
            # (docs/offload-home.md, Notes).
            case $_flags in
                *nocopy*)
                    printf '%s\n' "  ...PENDING ~/$_name -> $_dst [nocopy] (runbook: docs/offload-home.md):"
                    printf '%s\n' "        rm -rf $_dst"
                    printf '%s\n' "        mv $_home_path $_home_path.pre-offload"
                    printf '%s\n' "        mkdir -p $_dst"
                    printf '%s\n' "        ln -s $_dst $_home_path"
                    ;;
                *)
                    printf '%s\n' "  ...PENDING ~/$_name -> $_dst (runbook: docs/offload-home.md):"
                    printf '%s\n' "        caffeinate -dimsu ditto $_home_path $_dst"
                    printf '%s\n' "        # after quiescing the row (see runbook):"
                    printf '%s\n' "        rsync -aHAXn --delete --itemize-changes $_home_path/ $_dst/ | head"
                    printf '%s\n' "        rsync -aHAX --delete $_home_path/ $_dst/"
                    printf '%s\n' "        mv $_home_path $_home_path.pre-offload && ln -s $_dst $_home_path"
                    ;;
            esac
            _pending=$((_pending+1))
        fi
    elif [[ -e $_dst ]]; then
        # Nothing at $HOME but the offload copy exists — post-soak cleanup
        # removed the fallback, or a restore-from-backup: rebuild the link.
        printf '%s\n' "  ...relinking ~/$_name (offload copy present, link missing)"
        deploy_ln -sfn "$_dst" "$_home_path"
        _fixed=$((_fixed+1))
    fi
    # Absent everywhere: row not applicable on this machine yet — nothing.
done

# Soak-fallback nag: deleting the ~/<name>.pre-offload dirs is the runbook's
# only step the row walk above cannot see — keep saying it until it's done.
_fallbacks=0
for _row in "${offload_rows[@]}"; do
    _name=${_row%%|*}
    _rest=${_row#*|}
    case $_rest in
        *'|'*) _flags=${_rest#*|} ;;
        *) _flags= ;;
    esac
    if [[ -e $HOME/$_name.pre-offload ]]; then
        case $_flags in
            *regen*) printf '%s\n' "  ...soak fallback present: ~/$_name.pre-offload (regenerable — delete after one good tool run)" ;;
            *) printf '%s\n' "  ...soak fallback present: ~/$_name.pre-offload (keep for the full soak window — it is the rollback)" ;;
        esac
        _fallbacks=$((_fallbacks+1))
    fi
done

printf '%s\n' "  ...done ($_ok ok, $_pending pending, $_fixed fixed, $_broken broken, $_conflict conflicts, $_fallbacks fallbacks)"

# BROKEN is fatal: the volume side is canonical, so link-present +
# target-missing is missing data, and fragments from 10_dirs on would write
# into a dead path.
if (( _broken > 0 )); then
    printf '%s\n' "  ...FATAL: $_broken farm link(s) point at missing targets — investigate, then re-run (docs/offload-home.md)"
    return 1
fi
