# Babel remote environment

You are running in the `claude` container of the `claude-remote` stack on Babel (Unraid).

## Repos and worktrees
- Clone each repo once into `/workspace/repos/<host>/<owner>/<repo>` over https (e.g. `/workspace/repos/github.com/acme/api`). Git auth comes from `GH_TOKEN`/`GITLAB_TOKEN`; never use SSH remotes.
- Never work directly in `/workspace/repos/...`. Create your own worktree; the `-<id8>` suffix is required because cleanup finds your work by it:
  ```bash
  id8=${CLAUDE_SESSION_ID:0:8}
  repo=/workspace/repos/github.com/acme/api
  git -C "$repo" fetch origin
  git -C "$repo" worktree add -b "claude/<topic>-$id8" "/workspace/wt/api-$id8" origin/HEAD
  cd "/workspace/wt/api-$id8"
  ```
- Push with `git push -u origin HEAD`; open PRs/MRs with `gh pr create` / `glab mr create`. After the session ends, worktrees are removed only if clean and fully pushed.

## Docker
- `docker` talks to a private Docker-in-Docker daemon (`DOCKER_HOST=tcp://dind:2376`). Do not change `DOCKER_HOST` or use other daemons.
- Publish ports only in 18000–18099. From here reach them at `http://dind:<port>` (not localhost). The user opens them at `http://babel:<port>`.
- Bind mounts work only for paths under `/workspace`.
- Containers may create root-owned files; fix with `sudo chown -R claude:users <path>` before finishing.
- Docker storage is capped and pruned nightly: expect to re-pull images.

## Tools
- Browser: the `playwright` MCP server drives headless Chromium. Use it to check web apps you run, at `http://dind:<port>`; take a screenshot when it helps the user.
- Databases: `psql`, `mysql`, `redis-cli`, `sqlite3` reach services you publish on 18000–18099 via host `dind`.
- Also available: `rg`, `fd`, `jq`, `yq`, `shellcheck`, `gh`, `glab`; `context7` MCP for current library docs.

## Teardown (required)
When a task is finished and verified, before reporting back, stop everything you started:
`docker compose down -v --remove-orphans` for each compose project and `docker rm -f` for containers you ran directly; confirm with `docker ps -a`.
Leave things running only if the user explicitly asked, and say so in your reply. Leftovers are removed after 2 h idle or 24 h regardless.
