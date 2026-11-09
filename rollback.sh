#!/usr/bin/env bash
# Points the active symlink back at an earlier release without rebuilding.
# Without DEPLOY_RELEASE it picks the release just before the active one.
set -euo pipefail

: "${DEPLOY_TARGET:?DEPLOY_TARGET (ssh host or alias) is required}"
: "${DEPLOY_PATH:?DEPLOY_PATH (remote project folder) is required}"
link="${DEPLOY_LINK:-build}"
requested="${DEPLOY_RELEASE:-}"

[[ "$link" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid link name: $link" >&2; exit 1; }

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

remote_path=$(printf %q "$DEPLOY_PATH")
trap release_lock EXIT
acquire_lock

current=$(ssh "$DEPLOY_TARGET" "cd $remote_path; readlink $link")
releases=$(ssh "$DEPLOY_TARGET" "cd $remote_path; ls -1d $link.[0-9]* | sort -t. -k2 -n -r")
target="$requested"
[ -n "$target" ] || target=$(printf '%s\n' "$releases" | awk -v cur="$current" 'f{print;exit} $0==cur{f=1}')

[ -n "$target" ] || { echo "No earlier release to roll back to" >&2; exit 1; }
printf '%s\n' "$releases" | grep -qxF "$target" || { echo "Release not found: $target" >&2; exit 1; }
[ "$target" != "$current" ] || { echo "$target is already active" >&2; exit 1; }

echo "Rolling back $current -> $target"
swap_link "$target"
log_event "manual-rollback release=$target from=$current"
