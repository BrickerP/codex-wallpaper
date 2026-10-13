# Security

## Supported versions

Security fixes are provided for the latest `codex-wallpaper` release. The companion currently supports Codex Dream Skin exactly at `v1.5.20`.

## Reporting a vulnerability

Please use the repository's private GitHub Security Advisory reporting flow. Do not include credentials, private images, themes, or local filesystem contents in a public issue.

## Trust boundary

The companion runs locally with the invoking user's permissions. Review imported image paths before use. The installer and uninstaller manage only the companion skill directory and its command symlink; they do not manage Codex Dream Skin or user theme data.
