#!/usr/bin/env bash
# Writes the deploy key, pinned host key and a "deploy-target" ssh alias for the runner.
set -euo pipefail

install -d -m 700 ~/.ssh
printf '%s\n' "$INPUT_KEY" > ~/.ssh/deploy_key
chmod 600 ~/.ssh/deploy_key
printf '%s\n' "$INPUT_KNOWN_HOSTS" >> ~/.ssh/known_hosts
cat >> ~/.ssh/config <<CONFIG
Host deploy-target
  HostName $INPUT_HOST
  User $INPUT_USER
  Port $INPUT_PORT
  IdentityFile ~/.ssh/deploy_key
  IdentitiesOnly yes
  StrictHostKeyChecking yes
CONFIG
