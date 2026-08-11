#!/bin/zsh
set -eu
setopt NO_UNSET

readonly repo_root="${0:A:h:h}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-wallpaper-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT INT TERM

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

assert_fails() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$name: command unexpectedly succeeded"
  fi
}

assert_failure_contains() {
  local name="$1"
  local expected="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)"; then
    fail "$name: command unexpectedly succeeded"
  fi
  [[ "$output" == *"$expected"* ]] || fail "$name: output did not contain '$expected'"
}

test_home="$test_root/home"
codex_home="$test_root/codex-home"
mkdir -p "$test_home" "$codex_home/skills"
codex_home="${codex_home:A}"

run_install() {
  env HOME="$test_home" CODEX_HOME="$codex_home" zsh "$repo_root/scripts/install.zsh"
}

run_uninstall() {
  env HOME="$test_home" CODEX_HOME="$codex_home" zsh "$repo_root/scripts/uninstall.zsh" "$@"
}

skill_target="$codex_home/skills/codex-wallpaper"
command_target="$skill_target/scripts/codex-wallpaper.zsh"
command_link="$test_home/.local/bin/codex-wallpaper"

mkdir "$skill_target"
print 'foreign' > "$skill_target/foreign.txt"
assert_fails 'installer refuses unmanaged skill directory' run_install
assert_true 'unmanaged skill directory is preserved' test -f "$skill_target/foreign.txt"
rm -rf "$skill_target"

foreign_skill="$test_root/foreign-skill"
mkdir "$foreign_skill"
ln -s "$foreign_skill" "$skill_target"
assert_fails 'installer refuses skill target symlink' run_install
assert_true 'skill target remains a symlink' test -L "$skill_target"
assert_equal 'skill target symlink is unchanged' "$(readlink "$skill_target")" "$foreign_skill"
rm "$skill_target"

mkdir "$skill_target"
print 'wrong marker' > "$skill_target/.codex-wallpaper-managed"
assert_fails 'installer refuses wrong ownership marker' run_install
assert_equal 'wrong marker is preserved' "$(/bin/cat "$skill_target/.codex-wallpaper-managed")" 'wrong marker'
rm -rf "$skill_target"

mkdir -p "$test_home/.local/bin"
print 'foreign command' > "$command_link"
assert_fails 'installer refuses foreign command file' run_install
assert_true 'foreign command file is preserved' test -f "$command_link"
assert_true 'foreign command file is not converted to symlink' test ! -L "$command_link"
rm "$command_link"

foreign_command="$test_root/foreign-command"
print 'foreign command target' > "$foreign_command"
ln -s "$foreign_command" "$command_link"
assert_fails 'installer refuses foreign command symlink' run_install
assert_equal 'foreign command symlink is unchanged' "$(readlink "$command_link")" "$foreign_command"
rm "$command_link"

engine_sentinel="$test_home/.codex/codex-dream-skin-studio/engine-sentinel"
state_sentinel="$test_home/Library/Application Support/CodexDreamSkinStudio/state-sentinel"
theme_sentinel="$test_home/Library/Application Support/CodexDreamSkinStudio/themes/theme-sentinel"
image_sentinel="$test_home/Library/Application Support/CodexDreamSkinStudio/images/image-sentinel"
active_theme_sentinel="$test_home/Library/Application Support/CodexDreamSkinStudio/theme/active-theme-sentinel"
companion_state_sentinel="$test_home/Library/Application Support/CodexWallpaper/companion-state-sentinel"
sentinel_paths=(
  "$engine_sentinel"
  "$state_sentinel"
  "$theme_sentinel"
  "$image_sentinel"
  "$active_theme_sentinel"
  "$companion_state_sentinel"
)
sentinel_contents=(
  'engine-root-content'
  'application-support-state-content'
  'theme-library-content'
  'image-library-content'
  'active-theme-content'
  'companion-state-content'
)

for index in {1..${#sentinel_paths}}; do
  mkdir -p "${sentinel_paths[$index]:h}"
  print -r -- "$sentinel_contents[$index]" > "$sentinel_paths[$index]"
done

assert_sentinels_preserved() {
  local phase="$1"
  local index
  for index in {1..${#sentinel_paths}}; do
    assert_true "$phase preserves ${sentinel_paths[$index]:t}" test -f "$sentinel_paths[$index]"
    assert_equal "$phase preserves contents of ${sentinel_paths[$index]:t}" \
      "$(/bin/cat "$sentinel_paths[$index]")" "$sentinel_contents[$index]"
  done
}

run_install >/dev/null
assert_true 'install creates ownership marker' test -f "$skill_target/.codex-wallpaper-managed"
assert_equal 'install writes canonical ownership marker' \
  "$(/bin/cat "$skill_target/.codex-wallpaper-managed")" 'managed-by-codex-wallpaper'
assert_true 'install creates command symlink' test -L "$command_link"
assert_equal 'install command symlink target' "$(readlink "$command_link")" "$command_target"
assert_sentinels_preserved 'install'

companion_version_file="$skill_target/VERSION"
managed_version="$(/bin/cat "$companion_version_file")"
print '9.9.9-test' > "$companion_version_file"
assert_failure_contains 'installed mutation gate rejects wrong companion version' \
  'companion 版本必须精确为 0.1.0' \
  env HOME="$test_home" "$command_link" apply mutation-gate-probe
print -r -- "$managed_version" > "$companion_version_file"

print 'wrong marker' > "$skill_target/.codex-wallpaper-managed"
assert_failure_contains 'installed mutation gate rejects wrong marker' '缺少有效的 managed-owner 标记' \
  env HOME="$test_home" "$command_link" apply mutation-gate-probe
print 'managed-by-codex-wallpaper' > "$skill_target/.codex-wallpaper-managed"
assert_failure_contains 'canonical marker reaches engine-version gate' '变更要求 Dream Skin 1.5.12；当前为 缺失' \
  env HOME="$test_home" "$command_link" apply mutation-gate-probe

print 'stale local change' > "$skill_target/.update-probe"
run_install >/dev/null
assert_true 'update replaces stale companion program file' test ! -e "$skill_target/.update-probe"
assert_equal 'update preserves command symlink target' "$(readlink "$command_link")" "$command_target"
assert_sentinels_preserved 'update'

managed_marker="$(/bin/cat "$skill_target/.codex-wallpaper-managed")"
print 'foreign marker' > "$skill_target/.codex-wallpaper-managed"
assert_fails 'uninstaller refuses wrong ownership marker' run_uninstall --yes
assert_true 'wrong-marker refusal preserves skill' test -d "$skill_target"
assert_true 'wrong-marker refusal preserves command symlink' test -L "$command_link"
print -r -- "$managed_marker" > "$skill_target/.codex-wallpaper-managed"

rm "$command_link"
ln -s "$engine_sentinel" "$command_link"
assert_fails 'uninstaller refuses foreign command symlink' run_uninstall --yes
assert_true 'foreign-symlink refusal preserves skill' test -d "$skill_target"
assert_equal 'foreign-symlink refusal preserves symlink' "$(readlink "$command_link")" "$engine_sentinel"
rm "$command_link"
ln -s "$command_target" "$command_link"

assert_fails 'uninstaller requires --yes' run_uninstall
assert_true 'missing-confirmation refusal preserves skill' test -d "$skill_target"
assert_true 'missing-confirmation refusal preserves command symlink' test -L "$command_link"

run_uninstall --yes >/dev/null
assert_true 'uninstall removes installed skill path' test ! -e "$skill_target"
assert_true 'uninstall removes command symlink' test ! -L "$command_link"
assert_sentinels_preserved 'uninstall'

trash_matches=("$test_home"/.Trash/codex-wallpaper-*(N))
assert_equal 'uninstall creates one recoverable Trash entry' "${#trash_matches}" '1'
assert_true 'Trash entry retains ownership marker' test -f "$trash_matches[1]/.codex-wallpaper-managed"

print 'install/update/uninstall lifecycle: ok'
