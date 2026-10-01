#!/usr/bin/env bash
set -euo pipefail

name=main-fast-forward
config="$HOME/.config/$name"
bin="$HOME/.local/bin/$name"
units="$HOME/.config/systemd/user"

usage() {
    cat <<'EOF'
Usage: main-fast-forward.sh [--repo PATH]... [--scan PATH]...

Register checkouts and/or directories to scan every five minutes.
  --repo PATH   Add a checkout (repeatable)
  --scan PATH   Scan a directory recursively on every run (repeatable)
  --help        Show this help

Examples:
  bash scripts/ubuntu/main-fast-forward.sh --repo ~/Git/project --repo ~/Git/notes
  bash scripts/ubuntu/main-fast-forward.sh --scan ~/Git --repo ~/other/project
EOF
}

report() { printf '%s: %s\n' "$1" "$2" >&2; }

register() {
    local file=$1 path=$2
    [[ $path != *$'\n'* ]] || { report "$path" 'paths containing newlines are unsupported'; return 1; }
    if ! grep -Fqx -- "$path" "$file" 2>/dev/null; then
        printf '%s\n' "$path" >> "$file"
    fi
}

checkout() {
    local path=$1 root
    [[ -d $path ]] || { report "$path" 'not a directory'; return 1; }
    if [[ $(git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null) != true ]]; then
        report "$path" 'not a Git checkout'
        return 1
    fi
    root=$(git -C "$path" rev-parse --show-toplevel)
    realpath -e -- "$root"
}

update() {
    local repo=$1 remote merge old target worktree='' line path='' status
    if ! old=$(git -C "$repo" rev-parse --verify 'refs/heads/main^{commit}' 2>/dev/null); then
        report "$repo" 'no local main; skipped'
        return
    fi
    if ! remote=$(git -C "$repo" config --get branch.main.remote) ||
       ! merge=$(git -C "$repo" config --get branch.main.merge); then
        report "$repo" 'main has no upstream; skipped'
        return
    fi
    # Fetch just the configured upstream into FETCH_HEAD, not a potentially
    # customized remote fetch refspec that could overwrite a local branch.
    if ! git -C "$repo" fetch --quiet --no-tags --refmap= "$remote" "$merge"; then
        report "$repo" 'fetch failed; skipped'
        return
    fi
    if ! target=$(git -C "$repo" rev-parse --verify 'FETCH_HEAD^{commit}' 2>/dev/null); then
        report "$repo" 'main upstream missing; skipped'
        return
    fi
    [[ $old != "$target" ]] || return 0
    if ! git -C "$repo" merge-base --is-ancestor "$old" "$target"; then
        report "$repo" 'main diverged from upstream; skipped'
        return
    fi

    # git worktree list includes linked worktrees even when --repo names another checkout.
    while IFS= read -r line; do
        case $line in
            'worktree '*) path=${line#worktree } ;;
            'branch refs/heads/main') worktree=$path ;;
        esac
    done < <(git -C "$repo" worktree list --porcelain)

    if [[ -n $worktree ]]; then
        if ! status=$(git -C "$worktree" status --porcelain --untracked-files=normal); then
            report "$repo" 'cannot check main worktree; skipped'
        elif [[ -n $status ]]; then
            report "$repo" 'main worktree has local changes; skipped'
        elif git -C "$worktree" merge --ff-only --quiet "$target"; then
            printf '%s: fast-forwarded main\n' "$repo"
        else
            report "$repo" 'fast-forward failed; skipped'
        fi
    elif git -C "$repo" update-ref refs/heads/main "$target" "$old"; then
        printf '%s: fast-forwarded main (branch only)\n' "$repo"
    else
        report "$repo" 'branch changed while updating; skipped'
    fi
}

run() {
    local repo gitdir scan found
    declare -A seen=()
    for repo in "$config/repos" "$config/scans"; do
        [[ -f $repo ]] || continue
        if [[ $repo == "$config/repos" ]]; then
            while IFS= read -r found; do
                if [[ -d $found ]]; then process "$found"; else report "$found" 'checkout missing; skipped'; fi
            done < "$repo"
        else
            while IFS= read -r scan; do
                if [[ ! -d $scan ]]; then report "$scan" 'scan directory missing; skipped'; continue; fi
                while IFS= read -r -d '' gitdir; do
                    process "${gitdir%/.git}"
                done < <(find "$scan" -name .git -prune -print0)
            done < "$repo"
        fi
    done
}

process() {
    local repo=$1 common
    [[ $(git -C "$repo" rev-parse --is-inside-work-tree 2>/dev/null) == true ]] || return 0
    common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
    [[ -z ${seen[$common]+x} ]] || return 0
    seen[$common]=1
    update "$repo"
}

if [[ ${1:-} == --run && $# == 1 ]]; then
    run
    exit
fi

repos=() scans=()
while (( $# )); do
    case $1 in
        --repo|--scan)
            option=$1
            (( $# >= 2 )) && [[ -n $2 ]] || { usage >&2; exit 2; }
            if [[ $option == --repo ]]; then
                resolved=$(checkout "$2") || exit 1
                repos+=("$resolved")
            else
                [[ -d $2 ]] || { report "$2" 'not a directory'; exit 1; }
                scans+=("$(realpath -e -- "$2")")
            fi
            shift 2 ;;
        --help|-h) usage; exit ;;
        *) usage >&2; exit 2 ;;
    esac
done
(( ${#repos[@]} + ${#scans[@]} )) || { usage >&2; exit 2; }

mkdir -p "$config" "$HOME/.local/bin" "$units"
for repo in "${repos[@]}"; do register "$config/repos" "$repo"; done
for scan in "${scans[@]}"; do register "$config/scans" "$scan"; done
if ! cmp -s "$0" "$bin"; then install -m 755 "$0" "$bin"; fi

service="$units/$name.service"
timer="$units/$name.timer"
service_text="[Unit]
Description=Fast-forward local main branches

[Service]
Type=oneshot
ExecStart=%h/.local/bin/main-fast-forward --run"
timer_text="[Unit]
Description=Check main branches every five minutes

[Timer]
OnCalendar=*:0/5
Persistent=true
Unit=main-fast-forward.service

[Install]
WantedBy=timers.target"
changed=0 timer_changed=0
if [[ ! -f $service ]] || [[ $(<"$service") != "$service_text" ]]; then
    printf '%s\n' "$service_text" > "$service"
    changed=1
fi
if [[ ! -f $timer ]] || [[ $(<"$timer") != "$timer_text" ]]; then
    printf '%s\n' "$timer_text" > "$timer"
    changed=1 timer_changed=1
fi
if (( changed )); then systemctl --user daemon-reload; fi
if ! systemctl --user is-enabled --quiet "$name.timer"; then systemctl --user enable "$name.timer"; fi
if (( timer_changed )) && systemctl --user is-active --quiet "$name.timer"; then
    systemctl --user restart "$name.timer"
elif ! systemctl --user is-active --quiet "$name.timer"; then
    systemctl --user start "$name.timer"
fi
