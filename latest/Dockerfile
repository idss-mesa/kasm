# MESA KASM Ubuntu desktop — built from cyverse-vice/kasm-ubuntu `24.04`
# (the variant upstream publishes as vice/kasm/ubuntu:latest)
FROM kasmweb/ubuntu-noble-desktop:1.17.0-rolling-daily

LABEL org.label-schema.name="CyVerse VICE MESA KASM Ubuntu" \
      org.label-schema.description="KASM Ubuntu 24.04 GNOME desktop with agentic AI CLIs and MESA MCP servers for CyVerse VICE" \
      org.label-schema.url="https://cyverse.org" \
      org.label-schema.vcs-url="https://github.com/idss-mesa/kasm" \
      org.label-schema.vendor="CyVerse" \
      org.label-schema.schema-version="1.0.0"

USER root

ARG TARGETARCH=amd64
ARG GO_VERSION="1.25.5"
ARG GCM_VERSION="2.7.3"

# System dependencies: upstream set plus the MESA stack
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        lsb-release apt-transport-https ca-certificates curl wget gnupg \
        libfreetype6-dev pkg-config libx11-dev gcc gettext less \
        software-properties-common apt-utils glances htop nano sudo git tmux \
        unzip socat bubblewrap python3 python3-venv python3-pip \
        figlet lolcat s3fs fuse && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# GNOME session bits (upstream)
RUN apt-get update && \
    apt-get install -y --no-install-recommends gnome-session gnome-shell \
        gnome-control-center gnome-terminal gnome-system-monitor gnome-tweaks && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# kasm-user: passwordless sudo, bash as login shell (the base sets /bin/sh,
# which means desktop terminals never read ~/.bashrc)
RUN usermod -aG sudo -s /bin/bash kasm-user && \
    echo "kasm-user ALL=NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir -p /home/kasm-user/.irods /home/kasm-user/data-store /home/kasm-user/Desktop && \
    chown -R 1000:1000 /home/kasm-user

# Node.js 22 (MESA standard; upstream used 20)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Git Credential Manager
RUN wget -q https://github.com/git-ecosystem/git-credential-manager/releases/download/v${GCM_VERSION}/gcm-linux-x64-${GCM_VERSION}.deb -O /tmp/gcm.deb && \
    dpkg -i /tmp/gcm.deb && rm -f /tmp/gcm.deb
ENV GCM_CREDENTIAL_STORE=cache

# Go, then the iRODS MCP server (https://github.com/idss-mesa/irods-mcp-server)
RUN wget -q -c https://dl.google.com/go/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz -O - | tar -xz -C /usr/local && \
    git clone --depth 1 https://github.com/idss-mesa/irods-mcp-server /tmp/irods-mcp-server && \
    cd /tmp/irods-mcp-server && \
    CGO_ENABLED=0 GOPATH=/tmp/go GOCACHE=/tmp/go-cache /usr/local/go/bin/go build -o /usr/local/bin/irods-mcp-server ./cmd/main.go && \
    cd / && rm -rf /tmp/irods-mcp-server /tmp/go /tmp/go-cache

# GoCommands https://learning.cyverse.org/ds/gocommands/
RUN cd /usr/local/bin && \
    GOCMD_VER=$(curl -L -s https://raw.githubusercontent.com/cyverse/gocommands/main/VERSION.txt) && \
    curl -L -s https://github.com/cyverse/gocommands/releases/download/${GOCMD_VER}/gocmd-${GOCMD_VER}-linux-${TARGETARCH}.tar.gz | tar zxvf -

# AWS CLI
RUN curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# mesa-mcp and mesa-ducklake in a dedicated venv (cyverse-login uses
# /opt/mesa/bin/python3 for iRODS password obfuscation)
RUN /usr/bin/python3 -m venv /opt/mesa && \
    /opt/mesa/bin/pip install --no-cache-dir \
      git+https://github.com/idss-mesa/mesa-ducklake.git \
      git+https://github.com/idss-mesa/mesa-mcp.git && \
    ln -s /opt/mesa/bin/mesa-ducklake /usr/local/bin/

# FUSE for non-root users and the /osn mount root
RUN echo "user_allow_other" >> /etc/fuse.conf && \
    chmod 644 /etc/fuse.conf && \
    mkdir -p /osn && chmod 755 /osn && chown 1000:1000 /osn

USER kasm-user

# Agent CLIs: Claude Code, OpenAI Codex, Claude Code Router (AI Verde bridge)
RUN npm config set prefix /home/kasm-user/.npm-global && \
    npm install -g @anthropic-ai/claude-code @openai/codex @musistudio/claude-code-router && \
    npm cache clean --force

# Antigravity CLI (agy) and OpenCode
RUN mkdir -p /home/kasm-user/.cache/antigravity/staging && \
    curl -fsSL https://antigravity.google/cli/install.sh | bash
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path

# Shell: MESA prompt + landing screen
RUN echo ". /etc/profile.d/mesa-prompt.sh" >> /home/kasm-user/.bashrc && \
    echo 'if [[ $- == *i* ]] && [ -r /etc/motd ]; then /etc/motd; fi' >> /home/kasm-user/.bashrc && \
    printf '\n# upgrade GoCommands\ntimeout 10 sudo gocmd upgrade > /dev/null 2>&1 || true\n' >> /home/kasm-user/.bashrc && \
    printf 'set-option -g status off\nset -g mouse on\n' >> /home/kasm-user/.tmux.conf

ENV PATH="/home/kasm-user/.local/bin:/home/kasm-user/.npm-global/bin:/home/kasm-user/.opencode/bin:/usr/local/go/bin:/usr/games:${PATH}"

# ~/data-store is the CSI driver fuse mount point
WORKDIR /home/kasm-user/data-store

# ---------------------------------------------------------------------------
# Config / assets last so edits rebuild in seconds
# ---------------------------------------------------------------------------
USER root
COPY kasmvnc_defaults.yaml /usr/share/kasmvnc/kasmvnc_defaults.yaml
COPY --chmod=755 vnc_startup.sh /dockerstartup/vnc_startup.sh

COPY --chmod=755 01-custom /etc/motd
COPY mesa-prompt.sh /etc/profile.d/mesa-prompt.sh
COPY --chmod=755 mesa-init.sh /usr/local/bin/mesa-init.sh
COPY --chmod=755 osn-mount.sh /usr/local/bin/osn-mount.sh
COPY --chmod=755 configs/aiverde-setup.sh /usr/local/bin/aiverde-setup
COPY --chmod=755 configs/cyverse-login.sh /usr/local/bin/cyverse-login
COPY --chmod=755 configs/mesa-mcp-shim.sh /usr/local/bin/mesa-mcp

COPY --chown=1000:1000 configs/claude.json /home/kasm-user/.claude.json
COPY --chown=1000:1000 configs/codex-config.toml /home/kasm-user/.codex/config.toml
COPY --chown=1000:1000 configs/opencode.json /home/kasm-user/.config/opencode/opencode.json
COPY --chown=1000:1000 configs/antigravity-mcp_config.json /home/kasm-user/.gemini/config/mcp_config.json
RUN chown -R 1000:1000 /home/kasm-user

USER kasm-user

ENTRYPOINT [ "/dockerstartup/vnc_startup.sh" ]
