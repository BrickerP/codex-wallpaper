#!/bin/zsh
set -eu
setopt NO_UNSET

readonly repo_root="${0:A:h:h}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-wallpaper-uninstall-failure.XXXXXX")"
trap '/bin/rm -rf "$test_root"' EXIT INT TERM

fail() {
  print -u2 "FAIL [$1]"
  exit 1
}

assert_true() {
  local name="$1"
  shift
  "$@" || fail "$name"
}

assert_equal() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  [[ "$actual" == "$expected" ]] || fail "$name: expected '$expected', got '$actual'"
}

test_home="$test_root/home"
codex_home="$test_root/codex-home"
mkdir -p "$test_home" "$codex_home/skills"
codex_home="${codex_home:A}"

env HOME="$test_home" CODEX_HOME="$codex_home" zsh "$repo_root/scripts/install.zsh" >/dev/null

skill_target="$codex_home/skills/codex-wallpaper"
command_target="$skill_target/scripts/codex-wallpaper.zsh"
command_link="$test_home/.local/bin/codex-wallpaper"
fake_bin="$test_root/fake-bin"
mkdir "$fake_bin"
print '#!/bin/zsh' > "$fake_bin/rm"
print 'exit 73' >> "$fake_bin/rm"
chmod 755 "$fake_bin/rm"

if env HOME="$test_home" CODEX_HOME="$codex_home" PATH="$fake_bin:$PATH" \
  zsh "$repo_root/scripts/uninstall.zsh" --yes >/dev/null 2>&1; then
  fail 'uninstall unexpectedly succeeded when symlink removal failed'
fi

assert_true 'failed symlink removal preserves installed skill' test -d "$skill_target"
assert_true 'failed symlink removal preserves command symlink' test -L "$command_link"
assert_equal 'failed symlink removal preserves exact command target' \
  "$(readlink "$command_link")" "$command_target"

trash_matches=("$test_home"/.Trash/codex-wallpaper-*(N))
assert_equal 'failed symlink removal does not move skill to Trash' "${#trash_matches}" '0'

rm "$fake_bin/rm"
print '#!/bin/zsh' > "$fake_bin/mv"
print 'exit 74' >> "$fake_bin/mv"
chmod 755 "$fake_bin/mv"

if env HOME="$test_home" CODEX_HOME="$codex_home" PATH="$fake_bin:$PATH" \
  zsh "$repo_root/scripts/uninstall.zsh" --yes >/dev/null 2>&1; then
  fail 'uninstall unexpectedly succeeded when Trash move failed'
fi

assert_true 'failed Trash move preserves installed skill' test -d "$skill_target"
assert_true 'failed Trash move restores command symlink' test -L "$command_link"
assert_equal 'failed Trash move restores exact command target' \
  "$(readlink "$command_link")" "$command_target"

trash_matches=("$test_home"/.Trash/codex-wallpaper-*(N))
assert_equal 'failed Trash move leaves no moved skill in Trash' "${#trash_matches}" '0'

print 'uninstall symlink-removal and Trash-move rollback: ok'
