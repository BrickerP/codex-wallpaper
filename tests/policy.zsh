#!/bin/zsh
set -eu
setopt NO_UNSET

readonly repo_root="${0:A:h:h}"
readonly core="$repo_root/skill/codex-wallpaper/scripts"

fail() {
  print -u2 "policy failure: $1"
  exit 1
}

[[ -d "$core" ]] || fail 'missing executable core'
[[ ! -e "$repo_root/package.json" ]] || fail 'package.json is forbidden'

if grep -R -E -i '(watch(er)?|launchd|KeepAlive)' "$core" >/dev/null; then
  fail 'persistent automation token found in executable core'
fi

if grep -R -E -i '(fallback.{0,40}(start|restart)|(start|restart).{0,40}fallback)' "$core" >/dev/null; then
  fail 'start fallback found in executable core'
fi

if grep -E -i '(dream.skin.{0,40}(install|update)|(install|update).{0,40}dream.skin)' \
  "$repo_root/scripts/install.zsh" "$repo_root/scripts/uninstall.zsh" >/dev/null; then
  fail 'packaging scripts must not manage the upstream engine'
fi

print 'policy invariants: ok'
