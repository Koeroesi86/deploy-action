# deploy-action

Composite GitHub Action that deploys an **already built and tested** folder to a server over SSH.
It does not install, build or test anything: do that in your own `build` job and hand the output over as an artifact.

On the server it creates `<path>/<link>.<timestamp>/`, switches the `<path>/<link>` symlink to it atomically, and prunes old releases.

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

## Server setup

Use one deploy user per project that can write only `/var/www/<project>`, with its own key. Do not reuse a root key.

## Local use

`deploy.sh` works on its own: `DEPLOY_TARGET=myhost DEPLOY_PATH=/var/www/app DEPLOY_SOURCE=./build ./deploy.sh`
(optional `DEPLOY_LINK`, `DEPLOY_KEEP`, `DEPLOY_OWNER`).
