#!/bin/bash

### BEGIN INIT INFO
# Provides:          liteflow
# Required-Start:    $syslog
# Required-Stop:     $syslog
# Should-Start:      $local_fs
# Should-Stop:       $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Monitor for liteflow activity
# Description:       LiteFlow Port Forwarder
### END INIT INFO

# **NOTE** bash will not exit even if any command exits with non-zero.
#           the script will take care of the workflow.
set +e

PACKAGE_NAME=liteflow
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:${PATH}

# https://stackoverflow.com/a/246128
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PACKAGE_DIR=$(dirname "$SCRIPT_DIR")
PACKAGE_KEY=$(echo "$PACKAGE_DIR" | sed 's|/|_|g')

# Detect original user if running under sudo
REAL_USER=${SUDO_USER:-$USER}
REAL_HOME=$(eval echo ~$REAL_USER)

BIN_FILE="/usr/local/bin/liteflow"
CONF_FILE="/usr/local/etc/liteflow.conf"
LOG_FILE="/var/log/liteflow.log"
PID_FILE="/var/run/liteflow.pid"

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

# Loop through all passed arguments
# Skip the first argument (subcommand)
shifted_args=("${@:2}")
for arg in "${shifted_args[@]}"; do
  case "${arg,,}" in
    --local)
      BIN_FILE="$PACKAGE_DIR/bin/liteflow"
      CONF_FILE="$PACKAGE_DIR/etc/liteflow.conf"
      LOG_FILE="$PACKAGE_DIR/log/liteflow.log"
      PID_FILE="$PACKAGE_DIR/run/liteflow.pid"

      mkdir -p "$(dirname "$LOG_FILE")"
      mkdir -p "$(dirname "$PID_FILE")"
      ;;
  esac
done

CMD="$BIN_FILE -c $CONF_FILE"

check_pid() {
    # Check if PID file exists
    if [ ! -f "$PID_FILE" ]; then
        return 1
    fi

    PID=$(cat "$PID_FILE")
    if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
        log "Error: Invalid PID value in $PID_FILE"
        return 2
    fi

    if kill -0 "$PID" 2>/dev/null; then
        return 0  # Process is running
    else
        return 3  # PID file exists but process not running
    fi
}

start() {
    check_pid
    case $? in
        0)
            log "${PACKAGE_NAME} is already running (PID $(cat $PID_FILE))"
            return 1
            ;;
        2)
            return 1
            ;;
        3)
            log "Stale PID file found, removing."
            rm -f "$PID_FILE"
            ;;
    esac

    log -n "Starting ${PACKAGE_NAME}: "
    ulimit -c unlimited
    ulimit -n 65536

    if [ ! -d /etc/logrotate.d ]; then
        log -r "Logrotate directory not found, using logger output. Please install logrotate if needed."

        # Don't use nohup directly since it will print "nohup: redirecting stderr to stdout".
        # But if we use:
        # nohup bash -c "/usr/bin/env TZ=Asia/Shanghai $CMD 2>&1 | /usr/bin/logger -t ${PACKAGE_NAME}" >/dev/null 2>&1 &
        # Then the PID $! will be the parent "bash -c" PID.
        # That's why we use `disown` here.
        /usr/bin/env TZ=Asia/Shanghai $CMD 2>&1 | /usr/bin/logger -t ${PACKAGE_NAME} &
        disown
    else
        ROTATE_CONFIG="$LOG_FILE {
    daily
    rotate 7
    size=100k
    compress
    copytruncate
    missingok
    notifempty
    nocreate
    postrotate
    endscript
}"
        ROTATE_FILE="/etc/logrotate.d/liteflow.$PACKAGE_KEY"

        write_rotate_config() {
            echo "$ROTATE_CONFIG" | sudo tee "$ROTATE_FILE" > /dev/null
        }

        if [ -f "$ROTATE_FILE" ]; then
            CURRENT_CONTENT=$(cat "$ROTATE_FILE")
            if [ "$CURRENT_CONTENT" != "$ROTATE_CONFIG" ]; then
                if [ -w "$ROTATE_FILE" ]; then
                    echo "$ROTATE_CONFIG" > "$ROTATE_FILE"
                else
                    write_rotate_config
                fi
                log -r "Updated logrotate config at $ROTATE_FILE."
            else
                log -r "Logrotate config unchanged, skipping update."
            fi
        else
            if [ -w "$(dirname "$ROTATE_FILE")" ]; then
                echo "$ROTATE_CONFIG" > "$ROTATE_FILE"
            else
                write_rotate_config
            fi
            log -r "Created new logrotate config at $ROTATE_FILE."
        fi

        /usr/bin/env TZ=Asia/Shanghai $CMD 2>&1 >> $LOG_FILE &
        disown
    fi

    echo $! > "$PID_FILE"
    log "${PACKAGE_NAME} started (PID $(cat $PID_FILE))."
}

stop() {
    log -n "Stopping ${PACKAGE_NAME}: "
    check_pid
    case $? in
        0)
            pid=$(cat $PID_FILE)
            kill -9 $pid >/dev/null 2>&1 || true
            rm -f "$PID_FILE"
            log -r "${PACKAGE_NAME} stopped (PID $pid)."
            ;;
        1)
            log -r "No PID file found."
            return 1
            ;;
        2)
            return 1
            ;;
        3)
            log -r "Stale PID file, removing."
            rm -f "$PID_FILE"
            log "${PACKAGE_NAME} has not started."
            ;;
    esac
}

restart() {
    stop || true
    sleep 1
    start
}

reload() {
    log -n "Reloading ${PACKAGE_NAME}: "
    check_pid
    case $? in
        0)
            kill -10 $(cat "$PID_FILE") >/dev/null 2>&1 || true
            log -r "${PACKAGE_NAME} reloaded (PID $(cat $PID_FILE))."
            ;;
        1)
            log -r "No PID file found."
            return 1
            ;;
        2)
            return 1
            ;;
        3)
            log -r "Stale PID file, removing."
            rm -f "$PID_FILE"
            return 1
            ;;
    esac
}

status() {
    check_pid
    case $? in
        0)
            log "${PACKAGE_NAME} is running (PID $(cat $PID_FILE))"
            ;;
        1)
            log "${PACKAGE_NAME} is not running (no PID file)"
            ;;
        2)
            log "${PACKAGE_NAME}: PID file is corrupt"
            ;;
        3)
            log "${PACKAGE_NAME} is not running (stale PID file)"
            ;;
    esac
}

revive() {
    check_pid
    case $? in
        0)
            log "${PACKAGE_NAME} is already running (PID $(cat $PID_FILE))."
            ;;
        *)
            log "${PACKAGE_NAME} not running. Starting..."
            start
            ;;
    esac
}

update_conf_from_git() {
    REPO_URL="$1"
    REL_PATH="$2"

    if [ -z "$REPO_URL" ] || [ -z "$REL_PATH" ]; then
        log "Usage: update_conf_from_git <repo_url> <relative_path_to_json>"
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
            log "Updating $CONF_FILE with new version from repo (PID $(cat $PID_FILE))."
            cp "$SRC_FILE" "$CONF_FILE"
            reload
        else
            log "No changes detected in config file (PID $(cat $PID_FILE))."
        fi
    else
        log "cmp not available, overwriting $CONF_FILE without comparison."
        cp "$SRC_FILE" "$CONF_FILE"
        reload
    fi
}

usage() {
    N=$(basename "$0")
    log "Usage: $N {start|stop|restart|reload|status|revive|update_conf_from_git}" >&2
    log "Note: When the repository is accessed via an SSH URL, running sudo update_conf_from_git still relies on the invoking user's SSH key." >&2
    exit 1
}

# `readlink -f` won't work on Mac, this hack should work on all systems.

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    reload)
        reload
        ;;
    restart | force-reload)
        restart
        ;;
    status)
        status
        ;;
    revive)
        revive
        ;;
    update_conf_from_git)
        # Strip out all -x and --xxx arguments from $@
        filtered_args=()
        for arg in "${@:2}"; do
          case "$arg" in
            -*) ;; # skip
            --*) ;; # skip
            *) filtered_args+=("$arg") ;;
          esac
        done

        # export SSH key path from invoking user for git if running under sudo
        if [ -n "$SUDO_USER" ]; then
          export GIT_SSH_COMMAND="ssh -i $REAL_HOME/.ssh/id_rsa"
        fi

        update_conf_from_git "${filtered_args[@]}"
        ;;
    *)
        usage
        ;;
esac

exit 0
