#!/usr/bin/env bash
set -euo pipefail

script=$(realpath "$(dirname "$0")/main-fast-forward.sh")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
mkdir -p "$HOME" "$tmp/mock"
export MOCK_SYSTEMCTL="$tmp/mock"
systemctl() {
    local action=${2:-}
    case $action in
        daemon-reload) printf 'reload\n' >> "$MOCK_SYSTEMCTL/calls" ;;
        is-enabled|is-active) [[ -f "$MOCK_SYSTEMCTL/$action" ]] ;;
        enable|start|restart)
            printf '%s\n' "$action" >> "$MOCK_SYSTEMCTL/calls"
            [[ $action != enable ]] || touch "$MOCK_SYSTEMCTL/is-enabled"
            [[ $action != start ]] || touch "$MOCK_SYSTEMCTL/is-active" ;;
        *) return 1 ;;
    esac
}
export -f systemctl

make_repo() {
    local name=$1 location=$2
    git init -q --bare "$tmp/$name.git"
    git clone -q "$tmp/$name.git" "$tmp/$name-seed" 2>/dev/null
    git -C "$tmp/$name-seed" switch -q -c main
    git -C "$tmp/$name-seed" commit -q --allow-empty -m initial
    git -C "$tmp/$name-seed" push -q -u origin main
    git --git-dir="$tmp/$name.git" symbolic-ref HEAD refs/heads/main
    mkdir -p "$(dirname "$location")"
    git clone -q "$tmp/$name.git" "$location"
}
advance() {
    git -C "$tmp/$1-seed" commit -q --allow-empty -m next
    git -C "$tmp/$1-seed" push -q origin main
}
assert_equal() { [[ $1 == "$2" ]] || { printf 'expected %s, got %s\n' "$2" "$1" >&2; exit 1; }; }
tip() { git -C "$1" rev-parse refs/heads/main; }
remote_tip() { git -C "$tmp/$1-seed" rev-parse HEAD; }
run_updater() {
    "$HOME/.local/bin/main-fast-forward" --run >"$tmp/out" 2>"$tmp/err" || {
        printf 'updater failed:\n' >&2
        sed -n '1,100p' "$tmp/err" >&2
        return 1
    }
}

make_repo one "$tmp/one"
make_repo two "$tmp/two"
make_repo nested "$tmp/scan/a folder/b/c/nested"
make_repo worktree "$tmp/worktree"
make_repo dirty "$tmp/dirty"
make_repo diverged "$tmp/diverged"
make_repo branch "$tmp/branch"
if bash "$script" --repo "$tmp/not-a-checkout" >"$tmp/out" 2>"$tmp/err"; then
    printf 'invalid checkout accepted\n' >&2
    exit 1
fi
[[ ! -d "$HOME/.config/main-fast-forward" ]]

bash "$script" --repo "$tmp/one" --repo "$tmp/two" --repo "$tmp/dirty" \
    --repo "$tmp/diverged" --repo "$tmp/worktree" --repo "$tmp/branch" \
    --repo "$tmp/scan/a folder/b/c/nested" --scan "$tmp/scan"
[[ -f "$HOME/.config/systemd/user/main-fast-forward.timer" ]]
[[ $(wc -l < "$HOME/.config/main-fast-forward/repos") -eq 7 ]]
[[ $(wc -l < "$HOME/.config/main-fast-forward/scans") -eq 1 ]]
mtime=$(stat -c %y "$HOME/.config/systemd/user/main-fast-forward.timer")
service_mtime=$(stat -c %y "$HOME/.config/systemd/user/main-fast-forward.service")
bin_mtime=$(stat -c %y "$HOME/.local/bin/main-fast-forward")
cp "$MOCK_SYSTEMCTL/calls" "$tmp/initial-calls"
bash "$script" --repo "$tmp/one" --repo "$tmp/two" --scan "$tmp/scan"
cmp "$MOCK_SYSTEMCTL/calls" "$tmp/initial-calls"
assert_equal "$(stat -c %y "$HOME/.config/systemd/user/main-fast-forward.timer")" "$mtime"
assert_equal "$(stat -c %y "$HOME/.config/systemd/user/main-fast-forward.service")" "$service_mtime"
assert_equal "$(stat -c %y "$HOME/.local/bin/main-fast-forward")" "$bin_mtime"
[[ $(wc -l < "$HOME/.config/main-fast-forward/repos") -eq 7 ]]
run_updater
[[ ! -s "$tmp/out" && ! -s "$tmp/err" ]]

make_repo later "$tmp/scan/deep/deeper/later"
make_repo ignored "$tmp/ignored"
ln -s "$tmp/ignored" "$tmp/scan/symlink"
for name in one two nested dirty diverged worktree later branch ignored; do advance "$name"; done
touch "$tmp/dirty/untracked"
git -C "$tmp/diverged" commit -q --allow-empty -m local
git -C "$tmp/worktree" switch -q -c feature
linked="$tmp/scan/linked/main"
mkdir -p "$(dirname "$linked")"
git -C "$tmp/worktree" worktree add -q "$linked" main
git -C "$tmp/branch" switch -q -c feature
branch_head=$(git -C "$tmp/branch" rev-parse HEAD)
run_updater
for name in one two nested worktree later branch; do
    location="$tmp/$name"
    [[ $name == nested ]] && location="$tmp/scan/a folder/b/c/nested"
    [[ $name == later ]] && location="$tmp/scan/deep/deeper/later"
    assert_equal "$(tip "$location")" "$(remote_tip "$name")"
done
assert_equal "$(git -C "$linked" rev-parse HEAD)" "$(remote_tip worktree)"
assert_equal "$(git -C "$tmp/branch" rev-parse HEAD)" "$branch_head"
[[ $(git -C "$tmp/branch" symbolic-ref --short HEAD) == feature ]]
[[ $(tip "$tmp/dirty") != "$(remote_tip dirty)" ]]
[[ $(tip "$tmp/diverged") != "$(remote_tip diverged)" ]]
[[ $(tip "$tmp/ignored") != "$(remote_tip ignored)" ]]
[[ $(wc -l < "$tmp/out") -eq 6 ]]
[[ $(wc -l < "$tmp/err") -eq 2 ]]

advance worktree
touch "$linked/untracked"
run_updater
[[ $(tip "$tmp/worktree") != "$(remote_tip worktree)" ]]
[[ $(git -C "$linked" rev-parse HEAD) == "$(tip "$tmp/worktree")" ]]
rm "$linked/untracked" "$tmp/dirty/untracked"
run_updater
assert_equal "$(tip "$tmp/worktree")" "$(remote_tip worktree)"
assert_equal "$(tip "$tmp/dirty")" "$(remote_tip dirty)"
run_updater
[[ ! -s "$tmp/out" ]]

git -C "$tmp/one" branch --unset-upstream main
advance one
git -C "$tmp/two" remote set-url origin "$tmp/no-such-remote"
advance two
run_updater
[[ $(tip "$tmp/one") != "$(remote_tip one)" ]]
[[ $(tip "$tmp/two") != "$(remote_tip two)" ]]
[[ $(grep -c 'skipped' "$tmp/err") -eq 3 ]]
[[ ! -s "$tmp/out" ]]
git -C "$tmp/one" branch -m main renamed
run_updater
[[ $(grep -c 'no local main' "$tmp/err") -eq 1 ]]
[[ -z $(git -C "$tmp/one" branch --list main) ]]
printf 'main-fast-forward checks passed\n'
