#!/bin/zsh
set -eu
setopt NO_UNSET

readonly repo_root="${0:A:h:h}"

zsh -n "$repo_root/scripts/install.zsh" "$repo_root/scripts/uninstall.zsh" \
  "$repo_root/tests/lifecycle.zsh" "$repo_root/tests/policy.zsh" \
  "$repo_root/tests/run.zsh" "$repo_root/tests/uninstall-failure.zsh" \
  "$repo_root/tests/restart-protocol.zsh" \
  "$repo_root/skill/codex-wallpaper/scripts/codex-wallpaper.zsh"
node --check "$repo_root/skill/codex-wallpaper/scripts/theme-gallery.mjs"
node --check "$repo_root/skill/codex-wallpaper/scripts/verification-summary.mjs"
node --check "$repo_root/tests/verification.mjs"
zsh "$repo_root/tests/policy.zsh"
zsh "$repo_root/tests/lifecycle.zsh"
zsh "$repo_root/tests/uninstall-failure.zsh"
zsh "$repo_root/tests/restart-protocol.zsh"
node "$repo_root/tests/verification.mjs"
node "$repo_root/skill/codex-wallpaper/scripts/theme-gallery.mjs" --self-test

print 'all tests: ok'
