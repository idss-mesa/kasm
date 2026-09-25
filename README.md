# MESA KASM Ubuntu Desktop — CyVerse VICE

A full Ubuntu 24.04 GNOME desktop in the browser ([KasmVNC](https://kasmweb.com/kasmvnc)) for the **MESA** project, built to run as a [CyVerse Discovery Environment (VICE)](https://cyverse.org/discovery-environment) app, with the MESA agentic AI stack and CyVerse Data Store tooling.

![harbor](https://github.com/idss-mesa/kasm/actions/workflows/harbor.yml/badge.svg) ![platforms](https://img.shields.io/badge/platforms-linux%2Famd64-blue) ![registry](https://img.shields.io/badge/registry-harbor.cyverse.org%2Fvice%2Fmesa--kasm-0a7bbb)

Built from the `24.04` (published-as-`latest`) variant in [cyverse-vice/kasm-ubuntu](https://github.com/cyverse-vice/kasm-ubuntu), with the MESA agentic stack from [idss-mesa/jupyterlab](https://github.com/idss-mesa/jupyterlab) layered on top.

## What's inside

| Category | Tools |
| --- | --- |
| **Desktop** | KasmVNC on port 6901, GNOME session + terminal, Chrome/Firefox, VS Code, and the rest of the Kasm "deluxe" app set from the base |
| **AI agent CLIs** | Claude Code (`claude`), OpenAI Codex (`codex`), OpenCode (`opencode`), Antigravity (`agy`), Claude Code Router (`ccr`) |
| **MCP servers** | `irods` (CyVerse Data Store), `mesa` ([mesa-mcp](https://github.com/idss-mesa/mesa-mcp) + [mesa-ducklake](https://github.com/idss-mesa/mesa-ducklake)), `formation` ([formation-mcp](https://github.com/idss-mesa/formation-mcp), CyVerse DE), `filesystem` — pre-registered for every agent CLI |
| **AI Verde** | `aiverde-setup` helper wires OpenCode + Claude Code (via `ccr`) to `https://llm-api.cyverse.ai` |
| **CyVerse data** | GoCommands (`gocmd`), iRODS config, `s3fs`/OSN mounts (`osn-mount.sh`), AWS CLI |
| **Dev** | GitHub CLI (`gh`), Git Credential Manager, Go 1.25, Node.js 22 |

Base image: `kasmweb/ubuntu-noble-desktop:1.17.0-rolling-daily` (Ubuntu 24.04), from upstream's `24.04/` variant (what it publishes as `vice/kasm/ubuntu:latest`). Runs as `kasm-user` (uid 1000, bash); working dir `/home/kasm-user/data-store`.

## Run it

```bash
docker run --rm --shm-size=512m -p 6901:6901 -e IPLANT_USER=$USER harbor.cyverse.org/vice/mesa-kasm:latest
```

Then open <http://localhost:6901>. In VICE, register the tool on port **6901**. Open a terminal from the desktop to reach the agent CLIs.

## DE tool settings

These live in the Discovery Environment, not in this repo, and must match the image. Change them only together with the Dockerfile.

| Setting | Value |
| --- | --- |
| DE app | **MESA KASM Ubuntu Desktop** (`0f346e66-b92c-11f1-8dfa-008cfa5ae3e1`) |
| DE tool | `mesa-kasm` (`ff29a702-b92b-11f1-9483-008cfa5ae3e1`) |
| Image | `harbor.cyverse.org/vice/mesa-kasm:latest` |
| Type | interactive |
| Container port | **6901** |
| Working directory | `/home/kasm-user/data-store` (the Data Store CSI mount point; must match the Dockerfile `WORKDIR`) |
| UID | 1000 |
| Entrypoint override | none (the image's own startup script does the MESA per-user setup) |
| Max CPU | 32 cores (upstream `vice/kasm/ubuntu:24.04`) |
| Memory limit | 16 GiB (DE user cap; upstream 128 GiB) |

KasmVNC serves on 6901. `vnc_startup.sh` sources `~/.bashrc` under `set -e`, so any `.bashrc` line that errors aborts startup.

## Sign in to CyVerse

```bash
cyverse-login          # your CyVerse username + password
```

Writes the standard iRODS credential files (`~/.irods/`) so GoCommands, the `mesa`
and `formation` MCP servers, and the agents all act as **you** — with write/own
access to your home and shared collections. Without it you get anonymous, public
read-only access.

For the hosted CyVerse Data Store MCP, **Claude Code** registers **two** servers:
`irods` points at the anonymous
[public endpoint](https://mcp-public.cyverse.ai/mcp) (public data under
`/iplant/home/shared`, no sign-in) and works out of the box; `irods-auth` points
at the [authenticated endpoint](https://mcp.cyverse.ai/mcp), which uses CyVerse's
pre-registered OAuth client (`mcp-client`). Sign in to `irods-auth` once per
session to reach your private home collection:

```bash
claude mcp login irods-auth --no-browser   # opens a kc.cyverse.org URL; paste the redirect back
```

For private-collection access under OpenCode, Codex, and Antigravity, rely on
`cyverse-login`: the bundled **local** `mesa`/iRODS MCP servers and `gocmd` read
your `~/.irods` credentials directly (no OAuth) and act as you. Restart an agent
after logging in so its MCP servers pick up the credentials.

## Connect AI Verde LLMs

Each user authenticates with their **own** institutional identity — no API key is baked into the image. Inside a terminal:

```bash
aiverde-setup          # paste your key from chat.cyverse.ai → Course → API Key
```

It validates the key against `/v1/models`, lists your models, and writes `~/.config/aiverde/env` (chmod 600). Then:

- **OpenCode** — uses the `aiverde` provider directly.
- **Claude Code** — uses `ccr` for non-Anthropic models (`ccr code`), or the native `ANTHROPIC_BASE_URL` env path if your course serves Anthropic models.
- **Codex** — *not* wired to AI Verde: Codex dropped Chat Completions support and AI Verde does not serve the Responses API. It runs on its own OpenAI auth.
## Build

The build context is `latest/`:

```bash
make build             # linux/amd64 → harbor.cyverse.org/vice/mesa-kasm:latest
make run               # local smoke test
make push
```

The Dockerfile copies all config/asset files *after* the heavy layers, so editing configs rebuilds in seconds.

**CI:** pushes to `main` touching `latest/` — plus a weekly Sunday rebuild that tracks the upstream base image and agent-CLI releases — build and push `:latest` to Harbor ([`harbor.yml`](.github/workflows/harbor.yml)). hadolint lints the Dockerfile on PRs and trivy scans the published image weekly, reporting to the repo Security tab ([`security.yml`](.github/workflows/security.yml)). Both need the `HARBOR_USERNAME` / `HARBOR_PASSWORD` repo secrets.

## Layout

```
latest/
  Dockerfile                    image definition (KASM noble desktop + MESA agentic stack)
  vnc_startup.sh                container entrypoint (sources mesa-init, then starts KasmVNC + desktop)
  kasmvnc_defaults.yaml         KasmVNC server defaults
  mesa-init.sh                  per-user startup (iRODS config, Data Store dotfile import, .env files, S3/OSN mounts)
  01-custom                     MESA ANSI splash screen (/etc/motd)
  mesa-prompt.sh                shell prompt (/etc/profile.d)
  osn-mount.sh                  s3fs mounts for OSN/S3 buckets
  configs/                      agent-CLI configs + aiverde-setup / cyverse-login / mesa-mcp shim
Makefile                        local build/push/run
.github/workflows/              harbor.yml (build+push), security.yml (hadolint + trivy)
```

## Resources

- [CyVerse VICE apps](https://learning.cyverse.org/vice/) · [GoCommands](https://learning.cyverse.org/ds/gocommands/) · [AI Verde](https://aiverde-docs.cyverse.ai/) · [MESA docs](https://idss-mesa.github.io/docs/)
- Upstream: [cyverse-vice/kasm-ubuntu](https://github.com/cyverse-vice/kasm-ubuntu) · MESA org: <https://github.com/idss-mesa>
