# Linux Codex Installer

Simple local installer for the latest `openai/codex` Linux x86_64 binary.

## Features
- Checks the latest release from `https://github.com/openai/codex/releases/latest`.
- Downloads:
  - `codex-x86_64-unknown-linux-gnu.tar.gz`
  - `codex-x86_64-unknown-linux-gnu.sigstore`
- Verifies the downloaded tarball with `cosign` when available (identity/issuer constraints are enforced).
- Installs to `~/.local/bin/codex` by default (no root required).
- Shows and compares current install version before overwrite.
- Optional cleanup prompts for other `codex*` executables found in the install directory.
- Checks for other `codex` executables on PATH and reports which are outside the install directory.

## Requirements
- Linux x86_64.
- `curl` or `wget` for downloads.
- `cosign` for signature verification (optional; if not present install continues with a warning).

## Usage

### Check latest version

```bash
./scripts/install-codex.sh latest
```

### Install latest release (interactive)

```bash
./scripts/install-codex.sh install
```

### Install a specific version

```bash
./scripts/install-codex.sh install 0.114.0
```

### Status

```bash
./scripts/install-codex.sh status
```

### Uninstall

```bash
# remove only current ${INSTALL_DIR}/codex
./scripts/install-codex.sh uninstall

# remove only if current version matches requested
./scripts/install-codex.sh uninstall 0.114.0

# remove all codex* files in install directory
./scripts/install-codex.sh uninstall all
```

## Makefile targets

```bash
make latest
make status
make install
make install VERSION=0.114.0
make uninstall
make uninstall UNINSTALL_VERSION=all
```

You can override install location:

```bash
make install INSTALL_DIR=$HOME/bin
```

## Behavior notes

- `cosign` command is optional. If missing, the installer prints a warning and proceeds.
- Overwrite prompt shows `existing_version -> requested_version`.
- Extra local versions in the install directory are listed before overwrite and can be removed with a prompt (default `No`).
