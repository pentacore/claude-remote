FROM docker:29-cli AS dockercli
FROM golang:trixie AS go
# Stamp the release version (plain `go install` reports "DEV")
RUN v=$(go list -m -f '{{.Version}}' gitlab.com/gitlab-org/cli@latest) \
 && go install -ldflags "-X main.version=${v#v}" "gitlab.com/gitlab-org/cli/cmd/glab@$v"
FROM composer:2 AS composer
FROM node:26-trixie-slim AS node
FROM oven/bun:1-debian AS bun
FROM ghcr.io/astral-sh/uv:latest AS uv
FROM mikefarah/yq:4 AS yq

FROM debian:trixie-slim
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 TZ=Europe/Stockholm
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg git jq tmux openssh-server sudo procps less vim-tiny \
      unzip zip xz-utils build-essential pkg-config libssl-dev tzdata \
      ripgrep fd-find shellcheck rsync file tree sqlite3 postgresql-client default-mysql-client redis-tools \
      python3 python3-venv python3-pip \
      php-cli php-mbstring php-xml php-curl php-zip php-intl php-sqlite3 php-mysql php-pgsql php-bcmath php-gd \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Docker CLI: the real binary lives aside; /usr/local/bin/docker is the session-tagging shim
COPY --from=dockercli /usr/local/bin/docker /usr/libexec/docker-real/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/
COPY --from=go /usr/local/go /usr/local/go
COPY --from=go /go/bin/glab /usr/libexec/glab-real/glab
COPY --from=composer /usr/bin/composer /usr/local/bin/composer
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
COPY --from=uv /uv /uvx /usr/local/bin/
COPY --from=yq /usr/bin/yq /usr/local/bin/yq
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && ln -s bun /usr/local/bin/bunx \
 && ln -s /usr/bin/fdfind /usr/local/bin/fd \
 && npm install -g pnpm && npm cache clean --force

# Browser testing: Playwright MCP + its matching headless Chromium, shared read-only by all users
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN npm install -g @playwright/mcp@latest \
 && pw=$(node -p "require('path').dirname(require.resolve('playwright-core/package.json', {paths: ['/usr/local/lib/node_modules/@playwright/mcp']}))") \
 && node "$pw/cli.js" install --with-deps chromium \
 && chmod -R a+rX /opt/ms-playwright \
 && npm cache clean --force && rm -rf /var/lib/apt/lists/*

# Rust toolchain in the image; cargo registry/bins in the persisted home
ENV RUSTUP_HOME=/opt/rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | CARGO_HOME=/opt/cargo sh -s -- -y --no-modify-path --profile minimal -c clippy -c rustfmt

RUN useradd -u 99 -g 100 -d /home/claude -s /bin/bash -M claude \
 && usermod -p '*' claude \
 && echo 'claude ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/claude && chmod 0440 /etc/sudoers.d/claude \
 && chown -R 99:100 /opt/rustup /opt/cargo

COPY rootfs/ /
RUN chmod 0755 /usr/local/bin/* /usr/local/lib/claude-remote/hooks/*

ENV CARGO_HOME=/home/claude/.cargo \
    PATH=/usr/local/bin:/home/claude/.local/bin:/home/claude/.cargo/bin:/home/claude/go/bin:/opt/cargo/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DOCKER_HOST=tcp://dind:2376 DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH=/run/claude-remote/certs

WORKDIR /workspace
HEALTHCHECK --interval=5m --timeout=30s --start-period=3m \
  CMD runuser -u claude -- env HOME=/home/claude /usr/local/bin/healthcheck
ENTRYPOINT ["/usr/local/bin/claude-entrypoint"]
