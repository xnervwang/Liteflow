#!/bin/bash

# update-conf-from-git-repo.sh - Update liteflow configuration from git repository
#
# DESCRIPTION:
#   Downloads configuration from a git repository using fetch-conf.sh,
#   compares with current configuration, and reloads liteflow if changed.
#   Supports both global and local installation modes.
#
# USAGE:
#   update-conf-from-git-repo.sh [--local] <repo_url> <relative_path>
#
# OPTIONS:
#   --local     Use local mode (package directory configuration)
#               Global mode uses /usr/local/etc/liteflow.conf
#               Local mode uses <package_dir>/etc/liteflow.conf
#
# EXAMPLES:
#   update-conf-from-git-repo.sh git@github.com:user/configs.git server.conf
#   update-conf-from-git-repo.sh --local https://github.com:user/configs.git client.conf
#
# AUTHENTICATION:
#   For SSH: Add your SSH public key to the git repository
#   For HTTPS: Use personal access tokens in URL or git credential helper
#   See fetch-conf.sh documentation for detailed authentication methods
#
# NOTES:
#   - This script automatically creates backups before updating
#   - Only reloads liteflow if configuration actually changed
#   - Supports both global (/usr/local/etc/) and local (package/etc/) modes
#   - Uses fetch-conf.sh for git operations and file handling

set +e

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:${PATH}

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PACKAGE_DIR=$(dirname "$SCRIPT_DIR")
LITEFLOW_SCRIPT="${SCRIPT_DIR}/liteflow.sh"
FETCH_CONF_SCRIPT="${SCRIPT_DIR}/fetch-conf.sh"

LOCAL_OPT=""
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

check_required_commands() {
    local missing_commands=()
    
    # Check for grep (needed for parsing fetch-conf.sh output)
    if ! command -v grep >/dev/null; then
        missing_commands+=("grep")
    fi
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log "Error: Missing required command(s): ${missing_commands[*]}"
        log "Please install the missing command(s) before running this script."
        return 1
    fi
    
    return 0
}

check_dependencies() {
    if [ ! -f "$FETCH_CONF_SCRIPT" ]; then
        log "Error: fetch-conf.sh script not found at $FETCH_CONF_SCRIPT"
        return 1
    fi
    
    if [ ! -x "$FETCH_CONF_SCRIPT" ]; then
        log "Error: fetch-conf.sh script is not executable at $FETCH_CONF_SCRIPT"
        return 1
    fi
    
    if [ ! -f "$LITEFLOW_SCRIPT" ]; then
        log "Error: liteflow.sh script not found at $LITEFLOW_SCRIPT"
        return 1
    fi
    
    if [ ! -x "$LITEFLOW_SCRIPT" ]; then
        log "Error: liteflow.sh script is not executable at $LITEFLOW_SCRIPT"
        return 1
    fi
    
    return 0
}

reload_conf() {
    log "Reloading liteflow configuration..."
    "$LITEFLOW_SCRIPT" reload $LOCAL_OPT
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log "Configuration reloaded successfully"
    else
        log "Error: Failed to reload configuration (exit code: $exit_code)"
    fi
    
    return $exit_code
}

update_conf_from_git() {
    local repo_url="$1"
    local rel_path="$2"
    
    if [ -z "$repo_url" ] || [ -z "$rel_path" ]; then
        usage
        return 1
    fi
    
    log "Fetching configuration from git repository..."
    log "Repository: $repo_url"
    log "Source path: $rel_path"
    log "Target file: $CONF_FILE"
    
    # Use fetch-conf.sh to get the configuration file
    # The --backup option ensures we create a backup if the file is updated
    local fetch_output
    fetch_output=$("$FETCH_CONF_SCRIPT" git --backup "$repo_url" "$rel_path" "$CONF_FILE" 2>&1)
    local fetch_exit_code=$?
    
    # Log the fetch-conf.sh output
    echo "$fetch_output" | while IFS= read -r line; do
        log "fetch-conf: $line"
    done
    
    if [ $fetch_exit_code -ne 0 ]; then
        log "Error: Failed to fetch configuration from git repository (exit code: $fetch_exit_code)"
        return $fetch_exit_code
    fi
    
    # Check if the configuration was actually updated
    if echo "$fetch_output" | grep -q "Updating.*with new version\|Creating.*from repo"; then
        log "Configuration file was updated, reloading liteflow..."
        reload_conf
        if [ $? -eq 0 ]; then
            log "Liteflow configuration successfully updated and reloaded"
        else
            log "Warning: Configuration was updated but reload failed"
            return 1
        fi
    elif echo "$fetch_output" | grep -q "No changes detected"; then
        log "No changes detected in configuration file, reload skipped"
    else
        log "Configuration fetch completed (reload status unclear)"
    fi
    
    return 0
}

usage() {
    local script_name=$(basename "$0")
    log "Usage: $script_name [--local] <repo_url> <relative_path>" >&2
    log "Options:" >&2
    log "  --local     Use local mode (package directory configuration)" >&2
    log "Examples:" >&2
    log "  $script_name git@github.com:user/configs.git server.conf" >&2
    log "  $script_name --local https://github.com/user/configs.git client.conf" >&2
    log "Authentication:" >&2
    log "  For SSH: Add your SSH public key to the git repository" >&2
    log "  For HTTPS: Use personal access tokens in URL or git credential helper" >&2
    log "  See fetch-conf.sh documentation for detailed authentication methods" >&2
    exit 1
}

# Parse command line arguments
filtered_args=()
for arg in "$@"; do
    case "$arg" in
        --local)
            LOCAL_OPT="--local"
            CONF_FILE="$PACKAGE_DIR/etc/liteflow.conf"
            ;;
        --help|-h)
            usage
            ;;
        --*)
            log "Error: Unknown option $arg"
            usage
            ;;
        *)
            filtered_args+=("$arg")
            ;;
    esac
done

# Validate number of arguments
if [ ${#filtered_args[@]} -ne 2 ]; then
    log "Error: Expected 2 arguments, got ${#filtered_args[@]}"
    usage
fi

# Check required commands
if ! check_required_commands; then
    exit 1
fi

# Check dependencies
if ! check_dependencies; then
    exit 1
fi

# Create target directory if needed (for local mode)
target_dir=$(dirname "$CONF_FILE")
if [ ! -d "$target_dir" ]; then
    mkdir -p "$target_dir" || {
        log "Error: Failed to create target directory $target_dir"
        exit 1
    }
fi

# Execute configuration update
update_conf_from_git "${filtered_args[0]}" "${filtered_args[1]}"
exit $?
