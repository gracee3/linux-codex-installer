#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="openai"
REPO_NAME="codex"
REPO_TAG_PREFIX="rust-v"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/scripts}"
LATEST_RELEASE_SCRIPT="${REPO_ROOT}/scripts/install-codex.sh"

SOURCE_DIR="${CODEX_SOURCE_DIR:-${HOME}/git/codex}"
SOURCE_REMOTE="${CODEX_SOURCE_REMOTE:-$REPO_URL}"
ASSUME_YES="${CODEX_ASSUME_YES:-0}"
TAG_PATTERN='^rust-v[0-9]+(\.[0-9]+){2}[A-Za-z0-9._-]*$'

usage() {
  cat <<USAGE
Usage: source-install.sh [--yes] [--dir <path>] [--remote <url>] [--tag <release-tag>]

Examples:
  source-install.sh
  source-install.sh --dir ~/git/codex
  source-install.sh --tag rust-v0.114.0
  source-install.sh --yes

Description:
  Fetches and checks out the latest OpenAI Codex release tag in the source directory.
  Uses local git and runs with explicit confirmation before destructive reset fallback.

Options:
  --yes                     Accept prompts without asking (also CODEX_ASSUME_YES=1)
  --dir <path>              Source checkout directory (default: ${HOME}/git/codex)
  --remote <url>            Source remote to fetch tags from (default: $REPO_URL)
  --tag <tag>               Explicit tag to check out (supports rust-v0.114.0, 0.114.0, or v0.114.0; default: latest release)
  -h, --help               Show this help text

Environment:
  CODEX_SOURCE_DIR          Override default source directory
  CODEX_SOURCE_REMOTE       Override source remote URL
  CODEX_ASSUME_YES          Skip prompts when set to 1
USAGE
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

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

normalize_assume_yes() {
  ASSUME_YES="${ASSUME_YES,,}"
  if [ "$ASSUME_YES" = "true" ]; then
    ASSUME_YES=1
  elif [ "$ASSUME_YES" != "1" ]; then
    ASSUME_YES=0
  fi
}

resolve_latest_tag() {
  local release_version
  release_version="$( "$LATEST_RELEASE_SCRIPT" latest 2>/dev/null | awk 'NR==1 {print $1}' | tr -d '\r' | tr -d '[:space:]' )"
  if [ -z "$release_version" ]; then
    echo "Unable to resolve latest release from script: $LATEST_RELEASE_SCRIPT" >&2
    exit 1
  fi
  if [ -z "$release_version" ] || ! [[ "$release_version" =~ ^[0-9]+(\.[0-9]+){2}[A-Za-z0-9._-]*$ ]]; then
    echo "Resolved release version is invalid: ${release_version}" >&2
    exit 1
  fi
  printf '%s\n' "${REPO_TAG_PREFIX}${release_version}"
}

ensure_clean_git_repo() {
  local repo_dir="$1"

  if git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return
  fi

  if [ -e "$repo_dir" ]; then
    echo "Target path exists but is not a git repository: $repo_dir" >&2
    exit 1
  fi

  echo "Cloning ${REPO_OWNER}/${REPO_NAME} into $repo_dir..."
  git clone "$SOURCE_REMOTE" "$repo_dir"
}

git_safe_reset() {
  local repo_dir="$1"

  if ! prompt_yes_no "Working tree has local changes that may block checkout. Hard reset ${repo_dir} to HEAD and continue?"; then
    echo "Source update cancelled."
    exit 0
  fi

  git -C "$repo_dir" reset --hard
  git -C "$repo_dir" clean -fd
}

normalize_release_tag() {
  local input="$1"
  case "$input" in
    rust-v*)
      echo "$input"
      return
      ;;
    v[0-9]*)
      echo "${REPO_TAG_PREFIX}${input#v}"
      return
      ;;
    [0-9]*)
      echo "${REPO_TAG_PREFIX}${input}"
      return
      ;;
  esac

  echo "$input"
}

validate_release_tag() {
  local tag="$1"
  if ! [[ "$tag" =~ $TAG_PATTERN ]]; then
    echo "Invalid release tag format: $tag" >&2
    echo "Expected format: rust-v<semver> (for example rust-v0.114.0)" >&2
    exit 1
  fi
}

is_repo_dirty() {
  local repo_dir="$1"

  if git -C "$repo_dir" status --porcelain --untracked-files=normal | grep -q .; then
    return 0
  fi
  return 1
}

current_is_target_commit() {
  local repo_dir="$1"
  local tag="$2"

  local tag_commit
  local head_commit

  tag_commit="$(git -C "$repo_dir" rev-parse "${tag}^{commit}" 2>/dev/null || true)"
  if [ -z "$tag_commit" ]; then
    return 1
  fi

  head_commit="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || true)"
  [ -n "$head_commit" ] && [ "$head_commit" = "$tag_commit" ]
}

checkout_release_tag() {
  local repo_dir="$1"
  local tag="$2"

  if is_repo_dirty "$repo_dir"; then
    git_safe_reset "$repo_dir"
  fi

  if ! git -C "$repo_dir" fetch "$SOURCE_REMOTE" --tags --prune --prune-tags --force; then
    echo "Failed to fetch tags from remote: $SOURCE_REMOTE" >&2
    exit 1
  fi

  if ! git -C "$repo_dir" show-ref --verify --quiet "refs/tags/$tag"; then
    echo "Release tag not available after fetch: $tag" >&2
    exit 1
  fi

  if current_is_target_commit "$repo_dir" "$tag"; then
    local head_commit
    head_commit="$(git -C "$repo_dir" rev-parse HEAD)"
    echo "Already at ${tag} (commit ${head_commit})."
    return
  fi

  if [ -z "$tag" ]; then
    echo "Missing release tag to checkout." >&2
    exit 1
  fi

  local detached
  detached="$(git -C "$repo_dir" symbolic-ref --short -q HEAD || printf "HEAD")"
  if [ "$detached" = "HEAD" ]; then
    echo "Current HEAD is detached; switching directly to tag ${tag}."
  fi

  git -C "$repo_dir" checkout --detach -q "$tag"
  local commit_sha
  commit_sha="$(git -C "$repo_dir" rev-parse --short HEAD)"
  echo "Checked out ${tag} in ${repo_dir} (commit ${commit_sha})."
}

normalize_assume_yes
require_command git
require_command awk

if [ ! -x "$LATEST_RELEASE_SCRIPT" ]; then
  echo "Latest-release resolver missing: $LATEST_RELEASE_SCRIPT" >&2
  exit 1
fi

SELECTED_TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      ASSUME_YES=1
      shift
      ;;
    --dir)
      if [ $# -lt 2 ]; then
        echo "--dir requires an argument" >&2
        exit 1
      fi
      SOURCE_DIR="$2"
      shift 2
      ;;
    --dir=*)
      SOURCE_DIR="${1#*=}"
      shift
      ;;
    --remote)
      if [ $# -lt 2 ]; then
        echo "--remote requires an argument" >&2
        exit 1
      fi
      SOURCE_REMOTE="$2"
      shift 2
      ;;
    --remote=*)
      SOURCE_REMOTE="${1#*=}"
      shift
      ;;
    --tag)
      if [ $# -lt 2 ]; then
        echo "--tag requires an argument" >&2
        exit 1
      fi
      SELECTED_TAG="$2"
      shift 2
      ;;
    --tag=*)
      SELECTED_TAG="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$SELECTED_TAG" ]; then
  SELECTED_TAG="$(resolve_latest_tag)"
fi

SELECTED_TAG="$(normalize_release_tag "$SELECTED_TAG")"
validate_release_tag "$SELECTED_TAG"

if [ "${SOURCE_REMOTE#https://}" = "$SOURCE_REMOTE" ] && [ "${SOURCE_REMOTE#http://}" = "$SOURCE_REMOTE" ]; then
  echo "Remote URL must be set to an HTTP(S) Git remote: $SOURCE_REMOTE" >&2
  exit 1
fi

if [ -z "$SELECTED_TAG" ] || [ -z "$SOURCE_DIR" ]; then
  echo "SOURCE_DIR and tag must be set." >&2
  exit 1
fi

if [ "$SOURCE_DIR" = "/" ]; then
  echo "SOURCE_DIR must not be root." >&2
  exit 1
fi

case "$SOURCE_DIR" in
  "~")
    SOURCE_DIR="$HOME"
    ;;
  "~"/*)
    SOURCE_DIR="${HOME}${SOURCE_DIR:1}"
    ;;
esac

SOURCE_DIR_DIR="$(dirname "$SOURCE_DIR")"
if [ "$SOURCE_DIR_DIR" != "." ] && [ "$SOURCE_DIR_DIR" != "/" ]; then
  mkdir -p "$SOURCE_DIR_DIR"
fi

ensure_clean_git_repo "$SOURCE_DIR"
checkout_release_tag "$SOURCE_DIR" "$SELECTED_TAG"
