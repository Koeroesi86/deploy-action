#!/usr/bin/env bash
# Shared helpers for deploy.sh and rollback.sh. Expects DEPLOY_TARGET, remote_path and link to be set.

# Holds a server-side flock for as long as this script runs. The lock lives in a background ssh
# session, so it is released automatically if the script or the connection dies.
acquire_lock() {
  coproc LOCK { ssh "$DEPLOY_TARGET" "exec 9>$remote_path/.deploy.lock; flock -n 9 || { echo busy; exit 1; }; echo locked; cat > /dev/null"; }
  local line=""
  read -r line <&"${LOCK[0]}" || true
  [ "$line" = locked ] || { echo "Another deploy is running, or the lock could not be taken" >&2; exit 1; }
}

release_lock() {
  local fd="${LOCK[1]:-}"
  [ -z "$fd" ] || eval "exec $fd>&-"
}

# Points the active symlink at a release atomically.
swap_link() {
  ssh "$DEPLOY_TARGET" "set -e; cd $remote_path; ln -sfn $1 $link.next; mv -T $link.next $link"
}

# Appends a line to the remote deploy log.
log_event() {
  printf '%s %s actor=%s sha=%s run=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${DEPLOY_ACTOR:-${USER:-unknown}}" "${DEPLOY_SHA:-local}" "${DEPLOY_RUN_URL:-local}" \
    | ssh "$DEPLOY_TARGET" "cat >> $remote_path/.deploy-log"
}
