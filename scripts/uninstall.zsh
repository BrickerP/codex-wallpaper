#!/bin/zsh
set -eu
setopt NO_UNSET

if (( $# != 1 )) || [[ "$1" != '--yes' ]]; then
  print -u2 'usage: zsh scripts/uninstall.zsh --yes'
  exit 2
fi

readonly marker_value='managed-by-codex-wallpaper'
codex_home="${CODEX_HOME:-$HOME/.codex}"
codex_home="${codex_home:A}"

readonly skill_target="$codex_home/skills/codex-wallpaper"
readonly marker_path="$skill_target/.codex-wallpaper-managed"
readonly command_target="$skill_target/scripts/codex-wallpaper.zsh"
readonly command_link="$HOME/.local/bin/codex-wallpaper"

if [[ ! -d "$skill_target" || -L "$skill_target" || ! -f "$marker_path" || "$(<"$marker_path")" != "$marker_value" ]]; then
  print -u2 "error: refusing to remove unmanaged or missing target: $skill_target"
  exit 1
fi

if [[ ! -L "$command_link" || "$(readlink "$command_link")" != "$command_target" ]]; then
  print -u2 "error: refusing to remove without exact managed symlink: $command_link"
  exit 1
fi

trash_dir="$HOME/.Trash"
mkdir -p "$trash_dir"
trash_target="$trash_dir/codex-wallpaper-$(date +%Y%m%d%H%M%S)-$$"
[[ ! -e "$trash_target" ]] || { print -u2 "error: trash target exists: $trash_target"; exit 1; }

if ! rm "$command_link"; then
  print -u2 "error: could not remove managed symlink; companion was not moved: $command_link"
  exit 1
fi

if ! mv "$skill_target" "$trash_target"; then
  if [[ ! -e "$command_link" && ! -L "$command_link" ]]; then
    if ! ln -s "$command_target" "$command_link"; then
      print -u2 "error: uninstall failed and managed symlink rollback also failed: $command_link"
      exit 1
    fi
  fi
  print -u2 'error: could not move companion to Trash; managed symlink was restored'
  exit 1
fi

print "moved companion skill to $trash_target"
print 'preserved Dream Skin, state, themes, and images'
