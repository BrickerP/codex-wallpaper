#!/bin/zsh
set -eu
setopt NO_UNSET

readonly marker_value='managed-by-codex-wallpaper'
readonly repo_root="${0:A:h:h}"
readonly skill_source="$repo_root/skill/codex-wallpaper"

if [[ ! -d "$skill_source" || ! -x "$skill_source/scripts/codex-wallpaper.zsh" ]]; then
  print -u2 'error: repository skill/codex-wallpaper is incomplete'
  exit 1
fi

codex_home="${CODEX_HOME:-$HOME/.codex}"
mkdir -p "$codex_home/skills" "$HOME/.local/bin"
codex_home="${codex_home:A}"

readonly skill_target="$codex_home/skills/codex-wallpaper"
readonly marker_path="$skill_target/.codex-wallpaper-managed"
readonly command_target="$skill_target/scripts/codex-wallpaper.zsh"
readonly command_link="$HOME/.local/bin/codex-wallpaper"

if [[ -e "$skill_target" || -L "$skill_target" ]]; then
  if [[ ! -d "$skill_target" || -L "$skill_target" || ! -f "$marker_path" || "$(<"$marker_path")" != "$marker_value" ]]; then
    print -u2 "error: refusing to overwrite unmanaged target: $skill_target"
    exit 1
  fi
fi

if [[ -e "$command_link" || -L "$command_link" ]]; then
  if [[ ! -L "$command_link" || "$(readlink "$command_link")" != "$command_target" ]]; then
    print -u2 "error: refusing to overwrite unmanaged command: $command_link"
    exit 1
  fi
fi

stage="$(mktemp -d "$codex_home/skills/.codex-wallpaper.install.XXXXXX")"
backup=''
link_stage=''
installed=0

cleanup() {
  local exit_code=$?
  if (( exit_code != 0 )); then
    [[ -n "$link_stage" && ( -e "$link_stage" || -L "$link_stage" ) ]] && rm -f "$link_stage"
    if (( installed )) && [[ -d "$skill_target" ]]; then
      rm -rf "$skill_target"
    fi
    if [[ -n "$backup" && -d "$backup" && ! -e "$skill_target" ]]; then
      mv "$backup" "$skill_target"
    fi
  fi
  [[ -n "$stage" && -d "$stage" ]] && rm -rf "$stage"
  return $exit_code
}
trap cleanup EXIT INT TERM

cp -R "$skill_source/." "$stage/"
print -r -- "$marker_value" > "$stage/.codex-wallpaper-managed"
chmod 755 "$stage/scripts/codex-wallpaper.zsh"

if [[ -d "$skill_target" ]]; then
  backup="$codex_home/skills/.codex-wallpaper.previous.$$"
  [[ ! -e "$backup" ]] || { print -u2 "error: temporary target exists: $backup"; exit 1; }
  mv "$skill_target" "$backup"
fi

mv "$stage" "$skill_target"
stage=''
installed=1

link_stage="$HOME/.local/bin/.codex-wallpaper.link.$$"
ln -s "$command_target" "$link_stage"
mv -f "$link_stage" "$command_link"
link_stage=''

if [[ -n "$backup" ]]; then
  rm -rf "$backup"
  backup=''
fi

installed=0
print "installed codex-wallpaper at $skill_target"
print "command: $command_link"
