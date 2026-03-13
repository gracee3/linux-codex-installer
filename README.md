# Linux Codex Installer

A small, public-facing installer for the official `openai/codex` Linux x86_64 binary.

## What it does

- Resolves the latest release from `https://github.com/openai/codex/releases/latest`.
- Downloads `codex-x86_64-unknown-linux-gnu.tar.gz` and matching `.sigstore` bundle.
- Installs to `~/.local/bin/codex` by default (user-level, no `root` required).
- Supports overwrite flow with version comparison and prompts before removing alternatives.
- Supports local cleanup and audit of existing `codex` binaries on `PATH`.

## Supported platform

- Linux x86_64 (`x86_64` / `amd64`) only.

## Files

- [`scripts/install-codex.sh`](/home/emmy/git/linux-codex-installer/scripts/install-codex.sh): installer implementation.
- [`scripts/source-install.sh`](/home/emmy/git/linux-codex-installer/scripts/source-install.sh): syncs `~/git/codex` to the latest release tag.
- [`Makefile`](/home/emmy/git/linux-codex-installer/Makefile): convenience targets.
- [`config.toml`](/home/emmy/git/linux-codex-installer/config.toml): default repo Codex config for `make install config`.
- [`LICENSE`](/home/emmy/git/linux-codex-installer/LICENSE): project license for public use.

## Requirements

- `bash`
- `git`
- `curl` or `wget` for downloads.
- `tar` and `install`
- `cosign` (optional): required only if you want mandatory signature verification.

If `cosign` is missing, installation continues with a warning.

## Usage

### Basic script usage

```bash
./scripts/install-codex.sh latest
./scripts/install-codex.sh status
./scripts/install-codex.sh status config
./scripts/install-codex.sh install
./scripts/install-codex.sh install config
./scripts/install-codex.sh install 0.114.0
./scripts/install-codex.sh uninstall
./scripts/install-codex.sh uninstall 0.114.0
./scripts/install-codex.sh uninstall all
./scripts/source-install.sh
```

### Makefile targets

```bash
make latest
make status
make status config
make install
make install config
make install VERSION=0.114.0
make source-install
make source-install SOURCE_DIR=~/git/codex
make uninstall
make uninstall UNINSTALL_VERSION=all
```

### Source install target

```bash
make source-install
CODEX_ASSUME_YES=1 make source-install SOURCE_DIR=~/git/codex
./scripts/source-install.sh --dir ~/git/codex
```

This:
- Resolves the latest release tag from `openai/codex` (for example `rust-v0.114.0`)
- Accepts `--tag` values as `0.114.0`, `v0.114.0`, or `rust-v0.114.0`
- Fetches tags from GitHub and checks out that tag into the source directory
- Prompts before destructive reset if local changes would block checkout
- Falls back to `git reset --hard HEAD` + `git clean -fd` only after confirmation

### Install location override

```bash
make install INSTALL_DIR=$HOME/bin VERSION=0.114.0
```

### Non-interactive mode

Use `--yes` or env `CODEX_ASSUME_YES=1` for automation.

```bash
./scripts/install-codex.sh --yes install
# or
CODEX_ASSUME_YES=1 ./scripts/install-codex.sh uninstall all
```

## Verification behavior

Signature verification is attempted with:

```bash
cosign verify-blob --bundle <sigstore_file> \
  --certificate-identity-regexp '^https://github.com/openai/codex/.github/workflows/rust-release\\.yml@refs/tags/rust-v.*$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com <file>
```

The installer verifies the downloaded payload first, and falls back to the extracted binary signature if needed.

## Uninstall behavior

- `uninstall` removes only `INSTALL_DIR/codex` after confirm.
- `uninstall <version>` removes only when installed version matches.
- `uninstall all` removes `codex*` files in install dir after confirm.

## Version compatibility

- `install [version]` accepts `x.y.z` style versions (for example, `0.114.0`).
- `latest` always resolves the latest GitHub release tag `rust-v*` automatically.

## Environment variables

- `CODEX_INSTALL_DIR` — override default install location.
- `CODEX_ASSUME_YES=1` — skip prompts.
- `CODEX_HOME` — override config install path used by `install config` (default `~/.codex`).
- `CODEX_SOURCE_DIR` — override source checkout location for `source-install` (default `~/git/codex`).
- `CODEX_SOURCE_REMOTE` — override source git remote for `source-install`.
