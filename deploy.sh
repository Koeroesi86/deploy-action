#!/usr/bin/env bash
# Deploys an already built folder to a remote release directory over SSH.
# Layout on the remote: <path>/<link>.<timestamp>/ with <path>/<link> as a symlink to the active release.
set -euo pipefail

: "${DEPLOY_TARGET:?DEPLOY_TARGET (ssh host or alias) is required}"
: "${DEPLOY_PATH:?DEPLOY_PATH (remote project folder) is required}"
: "${DEPLOY_SOURCE:?DEPLOY_SOURCE (local built folder) is required}"
link="${DEPLOY_LINK:-build}"
keep="${DEPLOY_KEEP:-5}"
owner="${DEPLOY_OWNER:-}"

[ -d "$DEPLOY_SOURCE" ] || { echo "Source folder not found: $DEPLOY_SOURCE" >&2; exit 1; }
[[ "$link" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid link name: $link" >&2; exit 1; }
[[ "$keep" =~ ^[1-9][0-9]*$ ]] || { echo "DEPLOY_KEEP must be a positive integer" >&2; exit 1; }

release="$link.$(date +%s%3N)"
remote_path=$(printf %q "$DEPLOY_PATH")

echo "Uploading $DEPLOY_SOURCE to $DEPLOY_TARGET:$DEPLOY_PATH/$release"
tar -C "$DEPLOY_SOURCE" -cf - . | ssh "$DEPLOY_TARGET" "set -e; cd $remote_path; mkdir $release; tar --no-same-owner -xf - -C $release"

if [ -n "$owner" ]; then
  echo "Setting owner $owner"
  ssh "$DEPLOY_TARGET" "set -e; cd $remote_path; if [ \"\$(id -u)\" = 0 ]; then chown -R $(printf %q "$owner") $release; else sudo -n chown -R $(printf %q "$owner") $release; fi"
fi

echo "Activating $release"
ssh "$DEPLOY_TARGET" "set -e; cd $remote_path; ln -sfn $release $link.next; mv -T $link.next $link"

echo "Pruning old releases (keeping $keep)"
ssh "$DEPLOY_TARGET" "set -e; cd $remote_path; ls -1d $link.[0-9]* 2>/dev/null | sort -t. -k2 -n -r | tail -n +$((keep + 1)) | grep -vxF \"\$(readlink $link)\" | xargs -r rm -rf" || true

echo "Deployed $release"
