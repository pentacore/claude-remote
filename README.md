# claude-remote

Claude Code Remote Control on Babel (Unraid), with a capped Docker-in-Docker sidecar for running projects.

## How it works
- `claude`: Claude Code `remote-control` in tmux, toolchains (PHP, Node/TS, Python, Go, Rust), `gh`, `glab`.
- `dind`: private Docker daemon on a fixed-size loop image (`DIND_SIZE_GB`). Projects publish ports 18000–18099.
- Every container is tagged with its session. Cleanup: Claude tears down when done → SessionEnd hook → janitor every 10 min (orphans, 2 h idle, 24 h max, untagged after 1 h). Hourly and nightly (04:00) prunes; full prune at 75 % and emergency cleanup at 90 % storage.

## Images
GitHub Actions builds `ghcr.io/pentacore/claude-remote-claude` and `-dind` (linux/amd64) every Monday 03:00 UTC without cache, and on every change to `images/`. Tags: `latest`, `YYYY-MM-DD`, `sha-…`; set `IMAGE_TAG` to a date tag to roll back.

## Tools for Claude
- Baked in: ripgrep, fd, jq, yq, shellcheck, rsync, sqlite3, psql, mysql, redis-cli, headless Chromium.
- Seeded once at first start (user scope; remove them and they stay removed): `playwright` and `context7` MCP servers, `superpowers` and `mattpocock-skills` plugins. Set `CLAUDE_SEED=false` to skip. Anything else you install (`claude mcp add`, `/plugin install`) persists in `home/`.

## Deploy (Dockhand)
1. Data dir: make sure the `appdata` share lives only on the pool, then use its direct path as `DATA_DIR` (e.g. `/mnt/cache/appdata/claude-remote`).
2. Dockhand → Git repositories: add this repo (public, no credential needed).
3. Dockhand → Stacks → new git stack `claude-remote` on environment **Babel**, compose file `compose.yaml`.
4. Stack environment: copy `.env.example`; fill tokens and identity (see Accounts), `DATA_DIR`, and optionally `PERMISSION_MODE`.
5. Deploy (pulls the images).
6. Auto-update: on for `claude-remote-claude-1` (weekly images); off for `claude-remote-dind-1` — update dind by hand, since recreating it removes all running project containers.

## First run / re-login
```bash
docker exec -it -u claude claude-remote-claude-1 claude auth login
docker exec -it -u claude claude-remote-claude-1 tmux attach -t rc
```
Answer "Enable Remote Control?" and the workspace-trust prompt, then detach with `Ctrl-b d`. "Babel" appears in the Claude app's Remote Control list. When the login expires the container turns unhealthy; repeat both commands.

## Accounts
- One account each: `GH_TOKEN`, `GITLAB_TOKEN` (+ `GITLAB_HOST` for self-hosted), `GIT_NAME`, `GIT_EMAIL`.
- Several accounts: `GIT_TOKENS=github.com/acme=ghp_…;github.com=ghp_…;git.example.com=glpat_…` — the longest `host/owner` prefix matching the repo wins, for `git`, `gh` and `glab` alike. `GIT_IDENTITIES=github.com/acme=Jane Doe <jane@acme.example>` picks the commit identity the same way; `GIT_NAME`/`GIT_EMAIL` are the default.

## Permission mode
`PERMISSION_MODE` (default `auto`) applies to Remote Control sessions and to `claude` started over SSH. Invalid values fall back to `default` (see the container log).

## SSH / JetBrains Gateway
Set `ENABLE_SSH=true` plus `SSH_AUTHORIZED_KEYS` (separate keys with `;` or newlines) and/or `SSH_AUTHORIZED_KEYS_URL` (e.g. `https://github.com/<you>.keys`), redeploy. Then:
```bash
ssh -p 2222 claude@babel.your-tailnet.ts.net
```
Gateway → SSH connection → same host/port/user, project dir under `/workspace/wt/...`. `docker` in SSH/IDE sessions is tagged `manual` and survives until the 24 h ceiling.

## Operations
- Logs: Dockhand → container logs (`dind` shows janitor actions; `claude` shows supervisor/maintenance). Session teardown log: `/workspace/.claude-remote/logs/session-end.log`.
- Grow Docker storage: raise `DIND_SIZE_GB`, redeploy (shrinking is not supported; delete `dind/docker.img` with the stack stopped to recreate).
- Updates: `claude` follows the weekly image via Dockhand auto-update (this ends running Remote Control sessions, so keep Dockhand's update check at night). Claude Code also updates itself in between.
- Update dind: pull and recreate `claude-remote-dind-1` by hand when convenient; bump `DOCKER_MAJOR` (workflow + `.env`) deliberately.

## Development
```bash
make test-unit    # bats unit tests (in a container)
make test-cap     # loop-image cap test (needs privileged containers)
make test-stack   # full stack end-to-end (builds locally via compose.build.yaml)
make lint-ci      # actionlint for the workflow
```
