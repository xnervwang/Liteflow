#!/bin/bash

set +e

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:${PATH}

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PACKAGE_DIR=$(dirname "$SCRIPT_DIR")
PACKAGE_KEY=$(echo "$PACKAGE_DIR" | sed 's|/|_|g')

# Detect original user if running under sudo
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo ~$REAL_USER)

CONF_FILE="/usr/local/etc/liteflow.conf"

log() {
    if [ "$1" = "-n" ]; then
        shift
        printf "[%s] %s" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
    elif [ "$1" = "-r" ]; then
        shift
        printf "%s\n" "$*"
    else
        printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
    fi
}

# Handle --local first
for arg in "$@"; do
  case "${arg,,}" in
    --local)
      CONF_FILE="$PACKAGE_DIR/etc/liteflow.conf"
      ;;
  esac
done

update_conf_from_git() {
    REPO_URL="$1"
    REL_PATH="$2"

    if [ -z "$REPO_URL" ] || [ -z "$REL_PATH" ]; then
        usage
        return 1
    fi

    if ! command -v jq >/dev/null; then
        log "Warning: 'jq' is not installed. JSON validation will not be performed."
        NO_JQ=1
    else
        NO_JQ=0
    fi

    if ! command -v cmp >/dev/null; then
        log "Warning: 'cmp' is not installed. File comparison may not work."
        NO_CMP=1
    else
        NO_CMP=0
    fi

    TMP_DIR="/tmp/liteflow_git.$PACKAGE_KEY"
    if [ -d "$TMP_DIR/.git" ]; then
        log "Updating existing git repo at $TMP_DIR"
        cd "$TMP_DIR"
        git remote set-url origin "$REPO_URL" || true
        git fetch origin --depth=1
        git reset --hard origin/HEAD
        cd - >/dev/null || return 1
    else
        log "Cloning fresh repo to $TMP_DIR"
        rm -rf "$TMP_DIR"
        if ! git clone --depth=1 "$REPO_URL" "$TMP_DIR"; then
            log "Error: Failed to clone git repo."
            return 1
        fi
    fi

    SRC_FILE="$TMP_DIR/$REL_PATH"
    if [ ! -f "$SRC_FILE" ]; then
        log "Error: File $REL_PATH does not exist in repo."
        return 1
    fi

    if [ "$NO_JQ" -eq 0 ]; then
        if ! jq empty "$SRC_FILE" >/dev/null 2>&1; then
            log "Error: File $REL_PATH is not a valid JSON file."
            return 1
        fi
    fi

    if [ "$NO_CMP" -eq 0 ]; then
        if ! cmp -s "$SRC_FILE" "$CONF_FILE"; then
            log "Updating $CONF_FILE with new version from repo."
            cp "$SRC_FILE" "$CONF_FILE"
        else
            log "No changes detected in config file."
        fi
    else
        log "cmp not available, overwriting $CONF_FILE without comparison."
        cp "$SRC_FILE" "$CONF_FILE"
    fi
}

usage() {
    N=$(basename "$0")
    log "Usage: $N [--local] <repo_url> <relative_path_to_json>" >&2
    log "Note: If using SSH repo URL, 'sudo' will still use invoking user's SSH key at ~/.ssh/id_rsa." >&2
    exit 1
}

# Strip out flags from positional arguments
filtered_args=()
for arg in "$@"; do
  case "$arg" in
    --*) ;; # skip
    -*) ;; # skip
    *) filtered_args+=("$arg") ;;
  esac
done

if [ ${#filtered_args[@]} -ne 2 ]; then
    usage
fi

if [ -n "$SUDO_USER" ]; then
  export GIT_SSH_COMMAND="ssh -i $REAL_HOME/.ssh/id_rsa"
fi

update_conf_from_git "${filtered_args[0]}" "${filtered_args[1]}"

exit 0
