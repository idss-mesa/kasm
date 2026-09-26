# MESA KASM Ubuntu Desktop — CyVerse VICE

A full Ubuntu 24.04 XFCE desktop in the browser ([KasmVNC](https://kasmweb.com/kasmvnc)) for the **MESA** project, built to run as a [CyVerse Discovery Environment (VICE)](https://cyverse.org/discovery-environment) app, with the MESA agentic AI stack and CyVerse Data Store tooling.

![harbor](https://github.com/idss-mesa/kasm/actions/workflows/harbor.yml/badge.svg) ![platforms](https://img.shields.io/badge/platforms-linux%2Famd64-blue) ![registry](https://img.shields.io/badge/registry-harbor.cyverse.org%2Fvice%2Fmesa--kasm-0a7bbb)

Built from the `24.04` (published-as-`latest`) variant in [cyverse-vice/kasm-ubuntu](https://github.com/cyverse-vice/kasm-ubuntu), with the MESA agentic stack from [idss-mesa/jupyterlab](https://github.com/idss-mesa/jupyterlab) layered on top.

## What's inside

| Category | Tools |
| --- | --- |
| **Desktop** | KasmVNC on port 6901, XFCE session + terminal, Chrome/Firefox, VS Code, and the rest of the Kasm "deluxe" app set from the base |
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
| DE app | **MESA KASM Ubuntu Desktop** (`01b053c2-b936-11f1-95e9-008cfa5ae3e1`) |
| DE tool (version `1.0.0`) | `mesa-kasm` (`e380628e-b935-11f1-926e-008cfa5ae3e1`) |
| Image | `harbor.cyverse.org/vice/mesa-kasm:latest` |
| Type | interactive (`interactive: true`) |
| Network mode | `bridge` (Terrain's default `none` gives an analysis that runs but never serves) |
| Skip /tmp mount | `true` (VNC/X and IPC sockets live in /tmp) |
| VICE proxy | `interactive_apps` = cas-proxy (`discoenv/cas-proxy`), as on the featured apps |
| Container port | **6901** |
| Working directory | `/home/kasm-user/data-store` (the Data Store CSI mount point; must match the Dockerfile `WORKDIR`) |
| UID | 1000 |
| Entrypoint override | none (the image's own startup script does the MESA per-user setup) |
| Max CPU | 32 cores (upstream `vice/kasm/ubuntu:24.04`) |
| Memory limit | 16 GiB (the DE's cap for tools created or edited through the non-admin tools API; upstream 128 GiB) |

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

## GPU variant (`:gpu`)

`harbor.cyverse.org/vice/mesa-kasm:gpu` is built from [`gpu/Dockerfile`](gpu/Dockerfile) on top of `:latest`, so it has the same desktop, agent CLIs and MCP servers, plus:

| Category | Tools |
| --- | --- |
| **Desktop graphics** | OpenGL on the NVIDIA GPU for the whole XFCE session (Chrome, VS Code, Qt apps, and 3D apps you install such as Blender), VirtualGL 3.1.5 EGL back end (`mesa-gl-run <app>`), Vulkan ICD, `glxinfo` / `vulkaninfo` / `glmark2`; menu entries *GPU Monitor*, *GPU Check*, *GLX Spheres* |
| **PyTorch** | `torch 2.14.0+cu126`, `torchvision 0.29.0` in the conda env `pytorch` (Miniforge, `/opt/conda`): `conda activate pytorch`. Also numpy, pandas, matplotlib, ipykernel, `nvitop` |
| **Local LLMs** | [Ollama](https://ollama.com) 0.34.4, started with the desktop on `127.0.0.1:11434` (loopback only); `ollama-setup` connects Claude Code, Codex and OpenCode to it |
| **CUDA** | NVIDIA CUDA 13.4 forward-compat driver (`cuda-compat-13-4`, build arg `CUDA_COMPAT_VERSION`), used only on hosts older than R580 (see below) |
| **Tools** | `mesa-gpu-check`, `nvtop`, `nvitop` (on `PATH` without `conda activate`), GPU panel on the terminal landing screen |

The GPU image is about **23.3 GB** uncompressed (CPU `:latest`: 12.8 GB). Most of the difference is the PyTorch conda env (7.7 GB), Ollama (2.2 GB) and the CUDA forward-compat driver (0.5 GB).

The image has no NVIDIA driver: the NVIDIA container runtime injects the host's. An apt pin (`/etc/apt/preferences.d/mesa-no-nvidia-driver`) makes apt refuse the driver packages (`nvidia-driver-*`, `libnvidia-*`, `cuda-drivers`), which would shadow the injected driver and break `nvidia-smi`; CUDA toolkit packages such as `cuda-toolkit-12-x` still install. Delete that file (`sudo rm /etc/apt/preferences.d/mesa-no-nvidia-driver`) only if you really need a driver package in the container. `NVIDIA_DRIVER_CAPABILITIES=all` makes it inject the GL/EGL/Vulkan (`graphics`) and NVENC/NVDEC (`video`) libraries as well as CUDA. `NVIDIA_VISIBLE_DEVICES` is left to the device plugin / `docker --gpus`. PyTorch is not on `PATH` by default: `vnc_startup.sh` hashes the VNC password with `python3 -c "import crypt"`, and conda's Python 3.13 has no `crypt`.

### Run it locally

```bash
docker run --rm --gpus all --shm-size=1g -p 127.0.0.1:6901:6901 -e IPLANT_USER=$USER harbor.cyverse.org/vice/mesa-kasm:gpu
```

Or `make run-gpu`. Without `--gpus` the desktop still starts and renders with Mesa llvmpipe. The port is bound to loopback because the desktop has no password outside VICE (VICE's cas-proxy does the auth) and `kasm-user` has passwordless `sudo`. On a remote GPU server, tunnel to it (`ssh -L 6901:127.0.0.1:6901 <gpu-host>`) and open <http://localhost:6901> instead of publishing the port on all interfaces.

### OpenGL on the desktop

VICE pods get `/dev/nvidia*` but no `/dev/dri`, so KasmVNC's own `hw3d` (DRI3) cannot work, and with `hw3d: true` Xvnc exits with `Failed to create gbm`. `kasmvnc_defaults.yaml` keeps `hw3d: false`, and GL takes two other routes:

| Route | When |
| --- | --- |
| **Session default** (`MESA_GL_MODE=auto`) | When a GPU is present, the entrypoint exports `__GLX_VENDOR_LIBRARY_NAME=nvidia`, so every GLX app renders on the GPU straight into KasmVNC. `MESA_GL_MODE=mesa` goes back to llvmpipe. |
| **`mesa-gl-run <app>`** | VirtualGL's EGL back end (`vglrun -d egl`), for heavy 3D such as Blender, ParaView or napari 3D. It has the best throughput at large window sizes, and it adds Chrome's `VGL_CHROMEHACK` itself. |

NVIDIA does not document the session-default route for non-NVIDIA X servers. It worked in every app tested on R535 (T4), but check it with `mesa-gpu-check` on each new node driver; `mesa-gl-run` is the documented fallback. Vulkan works for compute and headless rendering. Vulkan presentation to Xvnc does not work.

The `MESA_*` switches (`MESA_GL_MODE`, `MESA_OLLAMA_AUTOSTART`, `MESA_DISABLE_CUDA_COMPAT`) are read once at container start, before `vnc_startup.sh` sources your `~/.env*` files, so setting them there has no effect. Set them as container environment variables instead: `docker run -e` locally; on VICE, as environment variables of the DE app (an *Environment Variable* parameter), not in `~/.env` files. Inside a running desktop you can move a single app off the session default yourself:

```bash
__GLX_VENDOR_LIBRARY_NAME=mesa <app>   # software GL (Mesa llvmpipe) for this app only
mesa-gl-run <app>                      # VirtualGL EGL on the GPU instead of NVIDIA GLX
```

### Local LLMs (Ollama)

```bash
ollama-setup                                   # pulls qwen3.5:9b and prints the commands below
ollama launch claude --model qwen3.5:9b        # Claude Code
codex --oss --local-provider ollama -m qwen3.5:9b
opencode -m ollama/qwen3.5:9b
```

Models that fit one 16 GB GPU (A16 / T4): `qwen3.5:9b` (default: tool calling, long context), `gpt-oss:20b` (Codex's default), `gemma4:12b`, `qwen3:4b`. Larger models spill to the CPU. The context is 32k tokens (`OLLAMA_CONTEXT_LENGTH`); Ollama's own one-GPU default of 4k is too small for agents. Models are stored in `~/.ollama/models` inside the container and are deleted when the analysis ends. `ollama stop <model>` frees GPU memory for PyTorch. `MESA_OLLAMA_AUTOSTART=0` stops the server from starting with the desktop.

### Check the GPU

```bash
mesa-gpu-check            # or Applications → System → GPU Check
mesa-gpu-check --ollama   # also runs qwen3:0.6b (~0.5 GB) and checks that it ran 100% on the GPU
```

It checks the driver, `libcuda`, CUDA forward-compat, PyTorch, Ollama, EGL, session GLX, VirtualGL and Vulkan, and exits 0 when nothing failed. Run it from a desktop terminal so it sees the same environment as the session's apps. It is the first thing to run when a DE tool was launched without a GPU.

### CUDA and driver compatibility

- **PyTorch** is the CUDA 12.6 build and runs on any driver from R525 up: R535 on T4, and R580+ on the DE's A16 nodes. Plain `pip install torch` from PyPI would get the CUDA 13 build, which needs R580+. The env's `pip.conf` pins `torch==2.14.0+cu126` and `torchvision==0.29.0+cu126`, so a package that needs a different torch fails to install instead of replacing it. Skip the pin once with `PIP_CONFIG_FILE=/dev/null pip install ...`. Once every node runs R580+, rebuild with `--build-arg TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130` for the CUDA 13 build.
- **Ollama 0.34.4** needs R550+ for its CUDA 12 runner and R580+ for CUDA 13; other CUDA 13 software needs R580+. On older drivers (R535/R550/R570) with a data-center GPU (A16, A100, T4), the entrypoint puts NVIDIA's CUDA 13.4 forward-compat driver (`/usr/local/cuda-13.4/compat`) on the session's `LD_LIBRARY_PATH`; `docker exec` / `kubectl exec` `bash -i` shells get the same through `/etc/bash.bashrc`. It does this only when the host CUDA API is below 13 *and* the compat driver initializes, and it never touches R580+ hosts. On a T4 with R535, desktop GL, VirtualGL, Vulkan and NVENC/NVDEC (ffmpeg) also worked with compat on. `MESA_DISABLE_CUDA_COMPAT=1` turns it off.
- **Version pins** are build args in `gpu/Dockerfile`: `CUDA_COMPAT_VERSION`, `TORCH_INDEX_URL`, `TORCH_VERSION`, `TORCHVISION_VERSION`, `OLLAMA_VERSION`/`OLLAMA_SHA256`, `VGL_VERSION`/`VGL_SHA256`, `MINIFORGE_VERSION`/`MINIFORGE_SHA256`. `CUDA_COMPAT_VERSION` (13.4) is the single compat pin: it sets both the `cuda-compat-13-4` package and `MESA_CUDA_COMPAT_DIR` (`/usr/local/cuda-13.4/compat`), and the build fails if that directory has no `libcuda.so.1`.

### Build & publish from a GPU server

`docker build` never uses a GPU, so the image is the same wherever it is built. The build host needs Docker with buildx and ~60 GB free disk, plus an NVIDIA GPU and nvidia-container-toolkit (`docker run --gpus`) for `make test-gpu`. On a GPU build host (for example the A100 server):

```bash
git clone https://github.com/idss-mesa/kasm && cd kasm
docker login harbor.cyverse.org
make pull-base build-gpu     # FROM harbor.cyverse.org/vice/mesa-kasm:latest → :gpu
GPU=0 make test-gpu          # GPU=<index> or GPU=all; ~3–5 min, needs internet (pulls qwen3:0.6b)
make push-gpu
```

`make build build-gpu` layers on a fresh local CPU build instead of the published one. `gpu/test-gpu.sh` runs these checks:

- **Static:** the host driver is injected, nothing is baked, the menu launchers are valid, uid 1000 can read every MESA file, and the apt pin leaves the driver packages with no install candidate (that part is skipped without network).
- **Start:** a VICE-like start (`--user 1000`, `IPLANT_USER`) serves KasmVNC on 6901, and Xvnc/XFCE are still up after 45 s.
- **Check:** `mesa-gpu-check --ollama` passes in the desktop session's environment.
- **Rendering:** VirtualGL, session GLX and Vulkan render on the allocated GPU; `__GLX_VENDOR_LIBRARY_NAME=mesa` moves one app to llvmpipe.
- **Terminal:** a desktop shell has `conda`, the system `python3` and a working `nvitop`; a `docker exec ... bash -i` shell gets the same CUDA forward-compat state as the desktop.
- **No GPU:** without a GPU, the desktop still starts and the check reports the missing GPU.

It prints a PASS/FAIL table and exits non-zero on any failure.

**CI:** [`harbor-gpu.yml`](.github/workflows/harbor-gpu.yml) is a manual alternative (Actions → harbor-gpu → Run workflow; inputs `base_tag`, `tag`). It builds on a GitHub runner, which has no GPU, so nothing is tested. It pins the CPU base by digest and pushes `:gpu`.

### DE tool settings (GPU)

The GPU tool is a copy of the CPU tool plus the GPU fields; the DE app is a copy of the CPU app pointing at it. [`gpu/de-tool.json`](gpu/de-tool.json) is the admin tool-import body (`POST /terrain/admin/tools`). The GPU fields and `container_devices` are admin-only. A `PATCH` that includes `container` replaces all container settings, so always send the complete object.

| Setting | Value |
| --- | --- |
| DE tool (version `1.0.0`) | `mesa-kasm-gpu` |
| Image | `harbor.cyverse.org/vice/mesa-kasm:gpu` |
| GPUs | `min_gpus` = `max_gpus` = **1**. If `min_gpus` is unset, the launch default of 0 gives no GPU. |
| GPU models | `["NVIDIA-A16"]` (must appear in `GET /terrain/tools/gpu-models`) |
| Shared memory | `container_devices`: `{"host_path": "/dev/shm", "container_path": "2Gi"}`. Kubernetes' default is 64 MiB, too small for Chrome and PyTorch. This is RAM-backed and counts against the memory limit. |
| CPU / memory | 4–8 cores; 16–32 GiB (`min_memory_limit` / `memory_limit`). 32 GiB is above the 16 GiB cap in the CPU table: that cap (`apps.tools.private.memory-limit`) applies only to the non-admin tools API, which silently lowers `memory_limit` to 16 GiB on create *and* edit. The admin import is not capped, so create and edit this tool only through the admin API. |
| Everything else | same as the CPU tool: `bridge`, skip /tmp mount, cas-proxy, port **6901**, `/home/kasm-user/data-store`, UID 1000, no entrypoint override; `pids_limit` 1024 (GPU tool) |

### Not done yet

KasmVNC can encode the desktop stream on the GPU (NVENC H.264/HEVC, `-videoCodec auto`, even without `/dev/dri`). In testing this cut Xvnc from ~40% to ~12% of a core. It needs a KasmVNC >= 1.5 base (`kasmweb/*:1.19.0-rolling-*`), and the 1.17.0 base's KasmVNC 1.3.4 rejects the option. Users would pick *H.264 NVENC* in the KasmVNC settings or open `/?stream_mode=-1029`.

## Build

The build context is `latest/`:

```bash
make build             # linux/amd64 → harbor.cyverse.org/vice/mesa-kasm:latest
make run               # local smoke test
make push
```

The Dockerfile copies all config/asset files *after* the heavy layers, so editing configs rebuilds in seconds.

**CI:** pushes to `main` touching `latest/` — plus a weekly Sunday rebuild that tracks the upstream base image and agent-CLI releases — build and push `:latest` to Harbor ([`harbor.yml`](.github/workflows/harbor.yml)). hadolint lints both Dockerfiles on PRs and trivy scans the published `:latest` and `:gpu` images weekly, reporting to the repo Security tab (until `:gpu` is first pushed, its scan is skipped with a warning) ([`security.yml`](.github/workflows/security.yml)). Both need the `HARBOR_USERNAME` / `HARBOR_PASSWORD` repo secrets.

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
gpu/                            NVIDIA GPU variant (:gpu), layered FROM the CPU image
  Dockerfile                    CUDA forward-compat, VirtualGL, Vulkan ICD, Ollama, PyTorch env
  common/                       shared by the five MESA GPU images (keep identical): entrypoint,
                                CUDA compat probe, mesa-gpu-check, ollama wrapper/setup, motd panel
  gpu-entrypoint.d/20-kasm-gl.sh  session GL mode (NVIDIA GLX or Mesa), sourced before vnc_startup.sh
  gpu-check.d/50-kasm-gl.sh     EGL / GLX / VirtualGL / Vulkan checks for mesa-gpu-check
  mesa-gl-run.sh                VirtualGL EGL launcher for heavy 3D apps
  nvidia_icd.json               Vulkan ICD (the NVIDIA toolkit does not inject one)
  applications/                 menu entries: GPU Monitor, GPU Check, GLX Spheres
  test-gpu.sh                   GPU smoke test (make test-gpu)
  de-tool.json                  DE admin tool-import body for mesa-kasm-gpu
Makefile                        local build/push/run (+ pull-base / build-gpu / test-gpu / push-gpu / run-gpu)
.github/workflows/              harbor.yml (build+push), harbor-gpu.yml (manual GPU build+push), security.yml (hadolint + trivy)
```

## Resources

- [CyVerse VICE apps](https://learning.cyverse.org/vice/) · [GoCommands](https://learning.cyverse.org/ds/gocommands/) · [AI Verde](https://aiverde-docs.cyverse.ai/) · [MESA docs](https://idss-mesa.github.io/docs/)
- Upstream: [cyverse-vice/kasm-ubuntu](https://github.com/cyverse-vice/kasm-ubuntu) · MESA org: <https://github.com/idss-mesa>
