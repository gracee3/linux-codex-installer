#!/usr/bin/env bash
set -euo pipefail

REPO="openai/codex"
ASSET_BASENAME="codex-x86_64-unknown-linux-gnu"
LATEST_RELEASE_URL="https://api.github.com/repos/${REPO}/releases/latest"
RELEASE_ASSET_URL="https://github.com/${REPO}/releases/download/rust-v%s/%s"
SIGSTORE_IDENTITY_REGEX='^https://github.com/openai/codex/.github/workflows/rust-release\.yml@refs/tags/rust-v.*$'
SIGSTORE_ISSUER='https://token.actions.githubusercontent.com'
DOWNLOAD_HEADERS=(
  -H "Accept: application/vnd.github+json"
  -H "User-Agent: codex-installer"
)
DOWNLOAD_TIMEOUT_SECONDS=20
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/scripts}"
REPO_CONFIG_FILE="${REPO_ROOT}/config.toml"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"

INSTALL_DIR="${CODEX_INSTALL_DIR:-${HOME}/.local/bin}"
ASSUME_YES="${CODEX_ASSUME_YES:-0}"

usage() {
  cat <<USAGE
Usage: install-codex.sh [--yes] [--install-dir <dir>] <command> [argument]

Commands:
  latest
    Print the latest release version.

  status
    Show codex executables currently discoverable on PATH and in install directory.

  status config
    Show the repository config.toml contents.

  install [version]
    Download and install the Linux x86_64 binary. If no version is provided, latest is used.

  install config
    Copy the repo config.toml to ${CODEX_HOME}/config.toml.

  uninstall [version|all]
    Remove installed binary at ${INSTALL_DIR}/codex.
    Specify version to remove only when current version matches.
    Use 'all' to remove every codex file in install directory.

Options:
  --yes                  Accept prompts without asking (also CODEX_ASSUME_YES=1)
  --install-dir <dir>    Override install directory (default: ${HOME}/.local/bin)
  -h, --help            Show this help text

  Environment:
  CODEX_INSTALL_DIR     Override install directory
  CODEX_ASSUME_YES      Skip prompts when set to 1
  CODEX_HOME            Override target config install directory (default: ${HOME}/.codex)
USAGE
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

prompt_yes_no() {
  local prompt="$1"

  if [ "$ASSUME_YES" = "1" ] || [ "$ASSUME_YES" = "true" ]; then
    return 0
  fi

  local response
  while true; do
    read -r -p "$prompt [y/N] " response
    case "${response,,}" in
      y|yes)
        return 0
        ;;
      ""|n|no)
        return 1
        ;;
      *)
        echo "Please answer y or n." >&2
        ;;
    esac
  done
}

download_text() {
  local url="$1"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL \
      --connect-timeout "$DOWNLOAD_TIMEOUT_SECONDS" \
      --max-time "${DOWNLOAD_TIMEOUT_SECONDS}" \
      "${DOWNLOAD_HEADERS[@]}" \
      "$url"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget --https-only --timeout="$DOWNLOAD_TIMEOUT_SECONDS" -q -O - "$url"
    return
  fi

  echo "Either curl or wget is required for network access." >&2
  exit 1
}

download_file() {
  local url="$1"
  local output_path="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL \
      --connect-timeout "$DOWNLOAD_TIMEOUT_SECONDS" \
      --max-time "${DOWNLOAD_TIMEOUT_SECONDS}" \
      "${DOWNLOAD_HEADERS[@]}" \
      "$url" -o "$output_path"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$output_path" "$url"
    return
  fi

  echo "Either curl or wget is required for network access." >&2
  exit 1
}

normalize_version() {
  local v="$1"
  case "$v" in
    ""|latest)
      echo "latest"
      ;;
    rust-v*)
      echo "${v#rust-v}"
      ;;
    v*)
      echo "${v#v}"
      ;;
    *)
      echo "$v"
      ;;
  esac
}

resolve_version() {
  local requested="$1"
  requested="$(normalize_version "$requested")"

  if [ "$requested" != "latest" ]; then
    if ! [[ "$requested" =~ ^[0-9]+(\.[0-9]+){2}[A-Za-z0-9._-]*$ ]]; then
      echo "Invalid version format: $requested" >&2
      exit 1
    fi
    printf '%s\n' "$requested"
    return
  fi

  local release_json tag_name
  release_json="$(download_text "$LATEST_RELEASE_URL")"
  tag_name="$(printf '%s\n' "$release_json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"rust-v\([^"]*\)".*/\1/p' | head -n 1)"

  if [ -z "$tag_name" ]; then
    echo "Unable to resolve latest codex release version." >&2
    exit 1
  fi

  printf '%s\n' "$tag_name"
}

asset_urls() {
  local version="$1"
  local tarball_file="${ASSET_BASENAME}.tar.gz"
  local sig_file="${ASSET_BASENAME}.sigstore"
  printf '%s\n' "$(printf "$RELEASE_ASSET_URL" "$version" "$tarball_file")"
  printf '%s\n' "$(printf "$RELEASE_ASSET_URL" "$version" "$sig_file")"
}

verify_binary() {
  local file_path="$1"
  local sigstore_path="$2"

  local verify_log
  verify_log="$(mktemp)"
  if ! cosign verify-blob \
    --bundle "$sigstore_path" \
    --certificate-identity-regexp "$SIGSTORE_IDENTITY_REGEX" \
    --certificate-oidc-issuer "$SIGSTORE_ISSUER" \
    "$file_path" >"$verify_log" 2>&1; then
    echo "Signature verification failed for $file_path:" >&2
    cat "$verify_log" >&2
    rm -f "$verify_log"
    return 1
  fi

  rm -f "$verify_log"
  return 0
}

extract_binary() {
  local archive="$1"
  local extract_dir="$2"

  tar -xzf "$archive" -C "$extract_dir"

  local extracted=""
  local candidate

  if [ -f "$extract_dir/$ASSET_BASENAME" ]; then
    extracted="$extract_dir/$ASSET_BASENAME"
  elif [ -f "$extract_dir/codex" ]; then
    extracted="$extract_dir/codex"
  fi

  if [ -z "$extracted" ]; then
    for candidate in "$extract_dir"/codex "$extract_dir"/codex-* "$extract_dir"/codex-*/*; do
      if [ -f "$candidate" ]; then
        extracted="$candidate"
        break
      fi
    done
  fi

  if [ -z "$extracted" ]; then
    local found
    found="$(find "$extract_dir" -maxdepth 2 -type f -name 'codex*' | head -n 1 || true)"
    if [ -n "$found" ]; then
      extracted="$found"
    fi
  fi

  if [ -z "$extracted" ] || [ ! -x "$extracted" ]; then
    echo "Unable to locate extracted executable from archive." >&2
    exit 1
  fi

  printf '%s\n' "$extracted"
}

binary_version() {
  local bin_path="$1"
  local version_output

  if [ ! -x "$bin_path" ]; then
    echo "n/a"
    return
  fi

  version_output="$($bin_path --version 2>/dev/null || true)"
  if [[ "$version_output" =~ ([0-9]+\.[0-9]+\.[0-9][A-Za-z0-9\.-]*) ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi

  echo "n/a"
}

collect_codex_in_path() {
  local -n out="$1"
  shift

  local -A seen=()
  local path_dirs=()
  local dir
  local candidate

  IFS=':' read -r -a path_dirs <<<"$PATH"

  for dir in "${path_dirs[@]}" "$@"; do
    [ -d "$dir" ] || continue
    shopt -s nullglob
    for candidate in "$dir"/codex "$dir"/codex-*; do
      [ -e "$candidate" ] || continue
      [ -x "$candidate" ] || continue

      local basename="${candidate##*/}"
      if [[ "$basename" != "codex" && "$basename" != codex-* ]]; then
        continue
      fi

      local resolved
      resolved="$(readlink -f "$candidate" 2>/dev/null || printf '%s' "$candidate")"
      if [ -n "${seen[$resolved]+x}" ]; then
        continue
      fi
      seen[$resolved]=1
      out+=("$candidate")
    done
    shopt -u nullglob
  done
}

status() {
  local mode="${1-}"

  if [ "$mode" = "config" ]; then
    if [ ! -f "$REPO_CONFIG_FILE" ]; then
      echo "Repository config not found: $REPO_CONFIG_FILE"
      return 1
    fi

    echo "Repository config: $REPO_CONFIG_FILE"
    echo "---"
    cat "$REPO_CONFIG_FILE"
    return 0
  fi

  if [ -n "$mode" ]; then
    echo "The 'status' command accepts only 'config' as an optional argument." >&2
    return 1
  fi

  local -a path_bins=()
  local -a install_bins=()
  local -A seen_path=()
  local resolved

  collect_codex_in_path path_bins
  collect_codex_in_path install_bins "$INSTALL_DIR"

  for bin in "${path_bins[@]}"; do
    resolved="$(readlink -f "$bin" 2>/dev/null || printf '%s' "$bin")"
    seen_path["$resolved"]=1
  done

  printf 'Install directory: %s\n' "$INSTALL_DIR"

  if [ ${#path_bins[@]} -eq 0 ]; then
    echo "No executable codex files were found on PATH."
  else
    echo "Executable codex files on PATH:"
    for bin in "${path_bins[@]}"; do
      printf '  %s\n    version: %s\n' "$bin" "$(binary_version "$bin")"
    done
  fi

  if [ ${#install_bins[@]} -eq 0 ]; then
    echo "No codex files were found in ${INSTALL_DIR}."
    return
  fi

  echo
  echo "Executable codex files in install directory:"
  for bin in "${install_bins[@]}"; do
    resolved="$(readlink -f "$bin" 2>/dev/null || printf '%s' "$bin")"
    if [ -n "${seen_path[$resolved]+x}" ]; then
      continue
    fi
    printf '  %s\n    version: %s\n' "$bin" "$(binary_version "$bin")"
  done
}

latest() {
  resolve_version latest
}

cleanup_tmp_dir() {
  if [ -n "${_run_install_tmp_dir:-}" ] && [ -d "$_run_install_tmp_dir" ]; then
    rm -rf "$_run_install_tmp_dir"
  fi
}

run_install() {
  local requested_version="$1"
  local version
  local tarball_path
  local sig_path
  local extracted_binary
  local target="${INSTALL_DIR}/codex"
  local tmp_dir

  if [ "$(uname -s)" != "Linux" ]; then
    echo "This installer supports Linux only." >&2
    exit 1
  fi

  if [ "$(uname -m)" != "x86_64" ] && [ "$(uname -m)" != "amd64" ]; then
    echo "This installer targets x86_64 Linux only." >&2
    exit 1
  fi

  version="$(resolve_version "$requested_version")"
  echo "Resolved version: $version"

  require_command cosign

  tmp_dir="$(mktemp -d)"
  _run_install_tmp_dir="$tmp_dir"
  trap cleanup_tmp_dir EXIT

  local -a asset_urls_arr=()
  mapfile -t asset_urls_arr < <(asset_urls "$version")
  if [ "${#asset_urls_arr[@]}" -lt 2 ]; then
    echo "Failed to resolve release asset URLs." >&2
    exit 1
  fi

  local tarball_url="${asset_urls_arr[0]}"
  local sig_url="${asset_urls_arr[1]}"

  tarball_path="$tmp_dir/${ASSET_BASENAME}.tar.gz"
  sig_path="$tmp_dir/${ASSET_BASENAME}.sigstore"

  download_file "$tarball_url" "$tarball_path"
  download_file "$sig_url" "$sig_path"
  extracted_binary="$(extract_binary "$tarball_path" "$tmp_dir")"

  if ! verify_binary "$extracted_binary" "$sig_path"; then
    echo "No valid signature was found for the extracted binary." >&2
    exit 1
  fi

  echo "Verified extracted binary with cosign."

  mkdir -p "$INSTALL_DIR"
  require_command install

  if [ -x "$target" ]; then
    local current
    current="$(binary_version "$target")"
    echo "Existing install: ${current} -> ${version}"

    if ! prompt_yes_no "Overwrite ${target}?"; then
      echo "Install cancelled."
      exit 0
    fi

    local -a removable_path_bins=()
    local -a other_path_bins=()

    collect_codex_in_path other_path_bins "$INSTALL_DIR"

    for bin in "${other_path_bins[@]}"; do
      if [ "$bin" = "$target" ]; then
        continue
      fi

      if [ "${bin%/*}" = "$INSTALL_DIR" ]; then
        removable_path_bins+=("$bin")
      fi
    done

    if [ ${#removable_path_bins[@]} -gt 0 ]; then
      echo
      echo "Other codex executables from ${INSTALL_DIR}:"
      for bin in "${removable_path_bins[@]}"; do
        printf '  %s (%s)\n' "$bin" "$(binary_version "$bin")"
      done
      echo
      if prompt_yes_no "Remove these additional local codex executables before install?"; then
        rm -f "${removable_path_bins[@]}"
        echo "Removed ${#removable_path_bins[@]} additional file(s)."
      fi
    fi

    local -a extra_path_bins=()
    for bin in "${other_path_bins[@]}"; do
      if [ "$bin" != "$target" ] && [ "${bin%/*}" != "$INSTALL_DIR" ]; then
        extra_path_bins+=("$bin")
      fi
    done

    if [ ${#extra_path_bins[@]} -gt 0 ]; then
      echo
      echo "Also found codex on PATH outside ${INSTALL_DIR}:"
      for bin in "${extra_path_bins[@]}"; do
        printf '  %s (%s)\n' "$bin" "$(binary_version "$bin")"
      done
      echo "These are outside ${INSTALL_DIR} and will not be removed automatically."
    fi
  fi

  install -m 0755 "$extracted_binary" "$target"
  echo "Installed codex ${version} to ${target}"
  trap - EXIT
  cleanup_tmp_dir

  if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
    echo "Note: ${INSTALL_DIR} is not on PATH. Add it with:"
    echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
  else
    echo "codex is ready at ${target}."
  fi
}

run_install_config() {
  local target="${CODEX_HOME}/config.toml"

  if [ ! -f "$REPO_CONFIG_FILE" ]; then
    echo "Repository config not found: $REPO_CONFIG_FILE" >&2
    return 1
  fi

  mkdir -p "${CODEX_HOME}"
  if [ -f "$target" ]; then
    if ! prompt_yes_no "Overwrite ${target}?"; then
      echo "Config install cancelled."
      return 0
    fi
  fi

  cp "$REPO_CONFIG_FILE" "$target"
  echo "Installed repository config to ${target}."
}

run_uninstall() {
  local requested="${1-}"
  local target="${INSTALL_DIR}/codex"

  if [ ! -e "$target" ] && [ "$requested" = "all" ]; then
    echo "No codex files to remove from ${INSTALL_DIR}."
    return 0
  fi

  if [ ! -e "$target" ] && [ -z "$requested" ]; then
    echo "No codex binary at ${target}."
    return 0
  fi

  if [ "$requested" = "all" ]; then
    if ! prompt_yes_no "Remove all codex files from ${INSTALL_DIR}?"; then
      echo "Uninstall cancelled."
      return 0
    fi

    rm -f "${INSTALL_DIR}"/codex* 2>/dev/null || true
    echo "Removed all codex files from ${INSTALL_DIR}."
    return 0
  fi

  if [ -n "$requested" ] && [ "$requested" != "all" ] && [ ! -x "$target" ]; then
    echo "No codex binary at ${target} to compare against requested version ${requested}."
    return 1
  fi

  if [ -n "$requested" ] && [ "$requested" != "all" ]; then
    local installed_version
    installed_version="$(binary_version "$target")"
    if [ "$installed_version" != "$requested" ] && [ "$installed_version" != "n/a" ]; then
      echo "Skipping removal: ${target} reports ${installed_version}, not ${requested}."
      echo "Use 'uninstall all' to remove all versions from ${INSTALL_DIR}."
      return 0
    fi
  fi

  if ! prompt_yes_no "Remove ${target}?"; then
    echo "Uninstall cancelled."
    return 0
  fi

  rm -f "$target"
  echo "Removed ${target}."
}

ASSUME_YES="${ASSUME_YES,,}"
if [ "$ASSUME_YES" = "true" ]; then
  ASSUME_YES=1
fi
if [ "$ASSUME_YES" != "1" ]; then
  ASSUME_YES=0
fi

command_name=""
command_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      ASSUME_YES=1
      shift
      ;;
    --install-dir)
      if [ $# -lt 2 ]; then
        echo "--install-dir requires an argument" >&2
        exit 1
      fi
      INSTALL_DIR="$2"
      shift 2
      ;;
    --install-dir=*)
      INSTALL_DIR="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    latest|status|install|uninstall)
      if [ -n "${command_name-}" ]; then
        command_args+=("$1")
        shift
        continue
      fi
      command_name="$1"
      shift
      ;;
    *)
      if [ -z "${command_name-}" ]; then
        echo "Unknown argument: $1" >&2
        usage
        exit 1
      fi
      command_args+=("$1")
      shift
      ;;
  esac
done

if [ -z "$command_name" ]; then
  usage
  exit 1
fi

if [ "${#command_args[@]}" -gt 1 ]; then
  echo "Only one optional argument is supported for this command." >&2
  exit 1
fi

case "$command_name" in
  latest)
    if [ "${#command_args[@]}" -gt 0 ]; then
      echo "The 'latest' command does not accept arguments." >&2
      exit 1
    fi
    latest
    ;;
  status)
    if [ "${#command_args[@]}" -gt 1 ]; then
      echo "Only one optional argument is supported for this command." >&2
      exit 1
    fi
    status "${command_args[0]-}"
    ;;
  install)
    if [ "${#command_args[@]}" -gt 1 ]; then
      echo "Only one optional argument is supported for this command." >&2
      exit 1
    fi

    if [ "${command_args[0]-}" = "config" ]; then
      run_install_config
      exit $?
    fi

    run_install "${command_args[0]-latest}"
    ;;
  uninstall)
    run_uninstall "${command_args[0]-}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
