#!/usr/bin/env bash
# Deploys an already built folder to a remote release directory over SSH.
# Layout on the remote: <path>/<link>.<timestamp>/ with <path>/<link> as a symlink to the active release.
# Steps: lock, upload, verify sha256 manifest, optional pre-activate command, atomic switch,
# optional health check with automatic rollback, deploy log, prune old releases.
set -euo pipefail

: "${DEPLOY_TARGET:?DEPLOY_TARGET (ssh host or alias) is required}"
: "${DEPLOY_PATH:?DEPLOY_PATH (remote project folder) is required}"
: "${DEPLOY_SOURCE:?DEPLOY_SOURCE (local built folder) is required}"
link="${DEPLOY_LINK:-build}"
keep="${DEPLOY_KEEP:-5}"
owner="${DEPLOY_OWNER:-}"
preActivate="${DEPLOY_PRE_ACTIVATE:-}"
healthUrl="${DEPLOY_HEALTH_URL:-}"
healthRetries="${DEPLOY_HEALTH_RETRIES:-10}"
healthDelay="${DEPLOY_HEALTH_DELAY:-3}"
rollbackOnFailure="${DEPLOY_ROLLBACK_ON_FAILURE:-true}"

[ -d "$DEPLOY_SOURCE" ] || { echo "Source folder not found: $DEPLOY_SOURCE" >&2; exit 1; }
[[ "$link" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid link name: $link" >&2; exit 1; }
[[ "$keep" =~ ^[1-9][0-9]*$ ]] || { echo "DEPLOY_KEEP must be a positive integer" >&2; exit 1; }
[[ "$healthRetries" =~ ^[1-9][0-9]*$ ]] || { echo "DEPLOY_HEALTH_RETRIES must be a positive integer" >&2; exit 1; }

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

release="$link.$(date +%s%3N)"
remote_path=$(printf %q "$DEPLOY_PATH")
manifest=$(mktemp)
created=""

cleanup() {
  local status=$?
  rm -f "$manifest"
  if [ "$status" -ne 0 ] && [ -n "$created" ]; then
    echo "Deploy failed, removing partial release $release" >&2
    ssh "$DEPLOY_TARGET" "rm -rf $remote_path/$release" || true
  fi
  release_lock
  exit "$status"
}
trap cleanup EXIT

acquire_lock

(cd "$DEPLOY_SOURCE" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum) > "$manifest"
fileCount=$(wc -l < "$manifest" | tr -d ' ')
[ "$fileCount" -gt 0 ] || { echo "Source folder has no files: $DEPLOY_SOURCE" >&2; exit 1; }

echo "Uploading $DEPLOY_SOURCE ($fileCount files) to $DEPLOY_TARGET:$DEPLOY_PATH/$release"
created=1
tar -C "$DEPLOY_SOURCE" -cf - . | ssh "$DEPLOY_TARGET" "set -e; cd $remote_path; mkdir $release; tar --no-same-owner -xf - -C $release"

echo "Verifying checksums"
ssh "$DEPLOY_TARGET" "set -e; cd $remote_path/$release; sha256sum --check --quiet -; test \"\$(find . -type f | wc -l)\" = $fileCount" < "$manifest"

if [ -n "$owner" ]; then
  echo "Setting owner $owner"
  ssh "$DEPLOY_TARGET" "set -e; cd $remote_path; if [ \"\$(id -u)\" = 0 ]; then chown -R $(printf %q "$owner") $release; else sudo -n chown -R $(printf %q "$owner") $release; fi"
fi

if [ -n "$preActivate" ]; then
  echo "Running pre-activate command"
  ssh "$DEPLOY_TARGET" "set -e; cd $remote_path/$release; bash -c $(printf %q "$preActivate")"
fi

previous=$(ssh "$DEPLOY_TARGET" "cd $remote_path; readlink $link || true")

echo "Activating $release"
swap_link "$release"
created=""
log_event "activated release=$release previous=${previous:-none}"

if [ -n "$healthUrl" ]; then
  echo "Checking $healthUrl"
  healthy=""
  for attempt in $(seq 1 "$healthRetries"); do
    curl -fsS --max-time 10 -o /dev/null "$healthUrl" && healthy=1 && break
    echo "Health check attempt $attempt/$healthRetries failed" >&2
    [ "$attempt" -eq "$healthRetries" ] || sleep "$healthDelay"
  done
  if [ -z "$healthy" ]; then
    if [ "$rollbackOnFailure" = "true" ] && [ -n "$previous" ]; then
      echo "Health check failed, rolling back to $previous" >&2
      swap_link "$previous"
      log_event "rolled-back release=$previous failed=$release"
    else
      echo "Health check failed, leaving $release active" >&2
    fi
    exit 1
  fi
fi

echo "Pruning old releases (keeping $keep)"
ssh "$DEPLOY_TARGET" "set -e; cd $remote_path; ls -1d $link.[0-9]* 2>/dev/null | sort -t. -k2 -n -r | tail -n +$((keep + 1)) | grep -vxF \"\$(readlink $link)\" | xargs -r rm -rf" || true

echo "Deployed $release"
