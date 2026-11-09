# deploy-action

Composite GitHub Action that deploys an **already built and tested** folder to a server over SSH.
It does not install, build or test anything: do that in your own `build` job and hand the output over as an artifact.

On the server it creates `<path>/<link>.<timestamp>/`, verifies every file against a sha256 manifest (and the file count), switches the `<path>/<link>` symlink atomically, and prunes old releases. If anything fails before the switch, the partial release is removed and the live release is untouched.

## Usage

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version-file: .nvmrc, cache: npm }
      - run: npm ci
      - run: npm test
      - run: npm run build
      - uses: actions/upload-artifact@v4
        with: { name: build, path: build }

  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/download-artifact@v4
        with: { name: build, path: build }
      - uses: Koeroesi86/deploy-action@v1
        with:
          host: ${{ vars.DEPLOY_HOST }}
          user: ${{ vars.DEPLOY_USER }}
          path: /var/www/donatr.eu
          source: build
          ssh-key: ${{ secrets.DEPLOY_SSH_KEY }}
          known-hosts: ${{ secrets.DEPLOY_KNOWN_HOSTS }}
```

The deploy job never rebuilds, so what ships is exactly what passed the tests.

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `host`, `user`, `port` | port `22` | SSH target |
| `ssh-key` | | Private key of a dedicated deploy user |
| `known-hosts` | | Output of `ssh-keyscan <host>`, so the host key is pinned |
| `path` | | Remote project folder |
| `source` | | Local built folder to ship |
| `link` | `build` | Symlink name; releases are `<link>.<timestamp>` |
| `keep` | `5` | Releases to keep, including the active one |
| `owner` | | Optional `user:group` to chown the release to (root or passwordless sudo) |
| `pre-activate` | | Command run on the server inside the new release before the switch; failure aborts and removes the release |
| `health-url` | | URL checked from the runner after the switch |
| `health-retries` | `10` | Health check attempts, 3 seconds apart |
| `rollback-on-failure` | `true` | Re-point the symlink at the previous release when the health check fails |

## Safety

- A server-side `flock` (`<path>/.deploy.lock`) stops two deploys or rollbacks running at once. It is released automatically if the run dies. Add `concurrency: deploy-<project>` to your own workflow as well, so GitHub queues runs instead of failing them.
- Every deploy and rollback appends a line (time, release, previous release, actor, commit, run URL) to `<path>/.deploy-log`.
- A failed health check leaves the broken release on disk for debugging; pruning removes it later.

## Manual rollback

```yaml
on:
  workflow_dispatch:
    inputs:
      release:
        description: Release folder to activate (empty = previous)
jobs:
  rollback:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: Koeroesi86/deploy-action/rollback@v1
        with:
          host: ${{ vars.DEPLOY_HOST }}
          user: ${{ vars.DEPLOY_USER }}
          path: /var/www/donatr.eu
          release: ${{ inputs.release }}
          ssh-key: ${{ secrets.DEPLOY_SSH_KEY }}
          known-hosts: ${{ secrets.DEPLOY_KNOWN_HOSTS }}
```

## Server setup

Use one deploy user per project that can write only `/var/www/<project>`, with its own key. Do not reuse a root key.

## Local use

`deploy.sh` and `rollback.sh` work on their own: `DEPLOY_TARGET=myhost DEPLOY_PATH=/var/www/app DEPLOY_SOURCE=./build ./deploy.sh`
(optional `DEPLOY_LINK`, `DEPLOY_KEEP`, `DEPLOY_OWNER`).
