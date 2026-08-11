# codex-wallpaper

An unofficial, dependency-free command companion for managing wallpapers through [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin). It supports exactly upstream version [`v1.5.12`](https://github.com/Fei-Away/Codex-Dream-Skin/tree/v1.5.12).

This repository does not include or install the Dream Skin engine, wallpapers, or images.

## Quick start

Prerequisites: macOS, `zsh`, `node`, Codex, and a separate working installation of Codex Dream Skin `v1.5.12`.

```zsh
git clone https://github.com/Yupeng-Lu/codex-wallpaper.git
cd codex-wallpaper
zsh scripts/install.zsh

codex-wallpaper list
codex-wallpaper status
codex-wallpaper gallery
codex-wallpaper apply "Theme name or ID"
codex-wallpaper restart-apply "Theme name or ID" --yes
codex-wallpaper import "/absolute/path/to/image.png" "Theme name"
```

`import` adds a theme but does not apply it. `restart-apply` is an explicit user action for cases where a normal apply cannot reach the running Codex window.

## Install and update

The installer atomically stages the repository's `skill/codex-wallpaper` directory into:

```text
${CODEX_HOME:-$HOME/.codex}/skills/codex-wallpaper
```

It then creates:

```text
$HOME/.local/bin/codex-wallpaper
  -> ${CODEX_HOME:-$HOME/.codex}/skills/codex-wallpaper/scripts/codex-wallpaper.zsh
```

Add `$HOME/.local/bin` to `PATH` if needed. To update, pull the repository and rerun `zsh scripts/install.zsh`.

The installer refuses to overwrite a skill directory without its exact companion ownership marker, or a command path that is not the exact managed symlink. It never installs, starts, restarts, or updates Dream Skin.

## Uninstall

```zsh
zsh scripts/uninstall.zsh --yes
```

The uninstaller requires `--yes`, verifies the ownership marker and exact symlink, moves the companion skill to `$HOME/.Trash`, and removes only that symlink. Dream Skin, its state, themes, and images are preserved.

## Data and security model

- Companion program files: `${CODEX_HOME:-$HOME/.codex}/skills/codex-wallpaper`
- Command symlink: `$HOME/.local/bin/codex-wallpaper`
- Dream Skin engine and state: owned by upstream and never managed by these packaging scripts
- Themes and images: remain in upstream/user-owned locations and are never bundled or removed here
- Gallery: a one-shot local interface; the companion does not install a persistent background service

Commands act only when invoked. Review image files and theme names before importing them. See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Troubleshooting

- **Unsupported or missing Dream Skin:** install upstream `v1.5.12` separately. This companion will not install or update it.
- **`codex-wallpaper: command not found`:** add `$HOME/.local/bin` to your shell `PATH`, then open a new shell.
- **Installer refuses a target:** move or remove the unrelated target yourself after inspecting it. The installer intentionally has no force mode.
- **Apply cannot reach Codex:** try `status`, ensure Codex and Dream Skin are working, then explicitly use `restart-apply` if a restart is acceptable.
- **Update:** pull this repository and rerun the installer; no separate updater exists.

## Development

There is no package manager, runtime dependency installation, build, or generated bundle.

```zsh
zsh tests/run.zsh
```

The test suite covers packaging policy, syntax, the gallery self-test, and a temporary-`HOME` install/update/uninstall lifecycle.

## License

MIT © 2026 Yupeng Lu. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
