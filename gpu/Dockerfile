# syntax=docker/dockerfile:1
# MESA KASM Ubuntu desktop — NVIDIA GPU variant. Adds GPU OpenGL/Vulkan for the
# desktop (VirtualGL EGL + NVIDIA GLX), CUDA PyTorch, Ollama and GPU tooling on
# top of the published CPU image; see ../README.md "GPU variant".
ARG BASE_IMAGE=harbor.cyverse.org/vice/mesa-kasm:latest

# cuda-probe: tiny glibc-only helper used by mesa-gpu-env.sh and mesa-gpu-check
FROM ubuntu:24.04 AS cuda-probe
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*
COPY --chmod=644 common/cuda-probe.c /src/cuda-probe.c
RUN gcc -O2 -Wall -o /cuda-probe /src/cuda-probe.c -ldl

FROM ${BASE_IMAGE}

LABEL org.label-schema.name="CyVerse VICE MESA KASM Ubuntu (NVIDIA GPU)" \
      org.label-schema.description="KASM Ubuntu 24.04 desktop with NVIDIA GPU OpenGL/Vulkan (VirtualGL), CUDA PyTorch, Ollama, agentic AI CLIs and MESA MCP servers for CyVerse VICE" \
      org.label-schema.url="https://cyverse.org" \
      org.label-schema.vcs-url="https://github.com/idss-mesa/kasm" \
      org.label-schema.vendor="CyVerse" \
      org.label-schema.schema-version="1.0.0"

USER root
# RUN under bash -o pipefail, as in cli/jupyterlab: every pipe below fails the build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Each version ARG is declared just above the first RUN that uses it: an ARG is
# part of the cache key of every later RUN, so an Ollama or CUDA compat bump
# declared up here would re-run the 7.7 GB PyTorch layer. For the same reason the
# CUDA forward-compat driver and Ollama are installed after PyTorch.

# apt pin: the NVIDIA driver packages (nvidia-driver-*, libnvidia-*, cuda-drivers)
# are never installable, in this build or later with `sudo apt install`.
COPY --chmod=644 common/apt-no-nvidia-driver.pref /etc/apt/preferences.d/mesa-no-nvidia-driver

# Build tools (curl, zstd), nvtop, and the NVIDIA apt repo (CUDA forward-compat
# driver only, installed further down; never driver packages).
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl zstd nvtop && \
    curl -fsSL -o /tmp/cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i /tmp/cuda-keyring.deb && rm -f /tmp/cuda-keyring.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Desktop GPU graphics. VICE pods get /dev/nvidia* but no /dev/dri, so KasmVNC's
# -hw3d (DRI3) is impossible; GL reaches the GPU through NVIDIA's GLX vendor
# library (session default, see gpu-entrypoint.d/20-kasm-gl.sh) or VirtualGL's
# EGL back end (mesa-gl-run). VirtualGL 3.1.5 replaces the base's 3.1.2: 3.1.3
# fixed an NVIDIA EGL resource leak, 3.1.4 added VGL_CHROMEHACK for Chrome >= 129.
ARG VGL_VERSION=3.1.5
ARG VGL_SHA256=df3f7788ce41b182a47c0d298e5cd6d2d63579522cb41825970b7726e825485e
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        vulkan-tools mesa-utils mesa-utils-bin glmark2-x11 libglu1-mesa libxtst6 libxv1 libegl1 && \
    curl -fsSL -o /tmp/virtualgl.deb \
        "https://github.com/VirtualGL/virtualgl/releases/download/${VGL_VERSION}/virtualgl_${VGL_VERSION}_amd64.deb" && \
    echo "${VGL_SHA256}  /tmp/virtualgl.deb" | sha256sum -c - && \
    apt-get install -y --no-install-recommends /tmp/virtualgl.deb && rm -f /tmp/virtualgl.deb && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# PyTorch (CUDA 12.6 wheels: the only CUDA 12 build of torch 2.14, runs on R535+
# drivers; PyPI's default torch is CUDA 13 and needs R580+) in a Miniforge env
# `pytorch` owned by kasm-user. /opt/conda is deliberately NOT on ENV PATH:
# vnc_startup.sh sources ~/.bashrc under `set -e` and hashes the VNC password
# with `python3 -c "import crypt"`, which conda's Python >= 3.13 no longer has.
# The env's pip.conf pins torch/torchvision so later `pip install`s cannot swap
# in a CUDA 13 build. matplotlib-base, not conda-forge's `matplotlib`: that adds
# the Qt6/PySide6 stack with two LLVMs (~1 GB); TkAgg covers plt.show().
# nvitop is symlinked onto PATH (the landing panel advertises it): its shebang is
# the env's python, so it runs without `conda activate` or conda's python3 on PATH.
ARG MINIFORGE_VERSION=26.7.2-0
ARG MINIFORGE_SHA256=281b0ac7d550802efc81af633225a5e6116d29ae72f3ab4eae7168c3931a4c05
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu126
ARG TORCH_VERSION=2.14.0
ARG TORCHVISION_VERSION=0.29.0
RUN curl -fsSL -o /tmp/miniforge.sh \
        "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-${MINIFORGE_VERSION}-Linux-x86_64.sh" && \
    echo "${MINIFORGE_SHA256}  /tmp/miniforge.sh" | sha256sum -c - && \
    bash /tmp/miniforge.sh -b -p /opt/conda && rm -f /tmp/miniforge.sh && \
    /opt/conda/bin/conda create -y -n pytorch python=3.13 pip numpy pandas matplotlib-base ipykernel && \
    /opt/conda/envs/pytorch/bin/pip install --no-cache-dir \
        "torch==${TORCH_VERSION}" "torchvision==${TORCHVISION_VERSION}" --index-url "${TORCH_INDEX_URL}" && \
    cu="${TORCH_INDEX_URL##*/}" && \
    printf 'torch==%s+%s\ntorchvision==%s+%s\n' "${TORCH_VERSION}" "$cu" "${TORCHVISION_VERSION}" "$cu" \
        > /opt/conda/envs/pytorch/torch-constraints.txt && \
    printf '[install]\nconstraint = /opt/conda/envs/pytorch/torch-constraints.txt\n' > /opt/conda/envs/pytorch/pip.conf && \
    /opt/conda/envs/pytorch/bin/pip install --no-cache-dir --extra-index-url "${TORCH_INDEX_URL}" nvitop nvidia-ml-py && \
    head -1 /opt/conda/envs/pytorch/bin/nvitop | grep -x '#!/opt/conda/envs/pytorch/bin/python[0-9.]*' >/dev/null && \
    ln -s /opt/conda/envs/pytorch/bin/nvitop /usr/local/bin/nvitop && \
    /opt/conda/envs/pytorch/bin/python -c 'import torch, torchvision; print(torch.__version__, torchvision.__version__)' && \
    /opt/conda/bin/conda clean -afy && \
    chown -R 1000:1000 /opt/conda

# One pin for the CUDA forward-compat driver: the apt package (cuda-compat-13-4)
# and its versioned path (MESA_CUDA_COMPAT_DIR, read by
# /etc/profile.d/mesa-gpu-env.sh) both derive from it, so a bump cannot leave
# the env pointing at a directory that does not exist.
ARG CUDA_COMPAT_VERSION=13.4
ENV MESA_CUDA_COMPAT_DIR=/usr/local/cuda-${CUDA_COMPAT_VERSION}/compat

# CUDA forward-compat driver from the NVIDIA repo added above, then the driver
# guard over everything apt installed. The NVIDIA runtime injects the host driver
# (libcuda, libEGL_nvidia, libGLX_nvidia, NVENC/NVDEC) at run time; a baked driver
# userspace would shadow it and break NVML. The guard's grep reads all of dpkg's
# output (no -q): with -q it exits at the first match, dpkg gets SIGPIPE and,
# under this pipefail SHELL, the check passes silently.
RUN apt-get update && apt-get install -y --no-install-recommends "cuda-compat-$(printf '%s' "${CUDA_COMPAT_VERSION}" | tr . -)" && \
    test -e "${MESA_CUDA_COMPAT_DIR}/libcuda.so.1" && \
    test ! -e /usr/local/cuda/compat && \
    if dpkg -l | grep -E '^ii +(nvidia-driver|nvidia-dkms|nvidia-utils|nvidia-compute-utils|libnvidia-(compute|gl|decode|encode|extra|fbc1|cfg1|common)|cuda-drivers)' >/dev/null; then \
        echo 'NVIDIA driver userspace must not be baked into the image' >&2; exit 1; fi && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ollama (pinned, sha256-checked; never install.sh — with no nvidia-smi at build
# time it installs cuda-drivers into the image)
ARG OLLAMA_VERSION=0.34.4
ARG OLLAMA_SHA256=c238986e61d40c0cc5f4a9b9e40b9eea104350b77efa34741fc134e105cb9533
RUN curl -fsSL -o /tmp/ollama.tar.zst "https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64.tar.zst" && \
    echo "${OLLAMA_SHA256}  /tmp/ollama.tar.zst" | sha256sum -c - && \
    zstd -dc /tmp/ollama.tar.zst | tar -xf - -C /usr/local && rm -f /tmp/ollama.tar.zst && \
    mv /usr/local/bin/ollama /usr/local/bin/ollama.bin

# ---------------------------------------------------------------------------
# Scripts / config / assets last so edits rebuild in seconds
# ---------------------------------------------------------------------------
# Explicit modes on every COPY: the result must not depend on the builder's umask
# or checkout permissions (uid 1000 has to read, and run, all of it).
COPY --from=cuda-probe --chmod=755 /cuda-probe /usr/local/bin/cuda-probe
COPY --chmod=644 common/mesa-gpu-env.sh /etc/profile.d/mesa-gpu-env.sh
COPY --chmod=755 common/ollama-wrapper.sh /usr/local/bin/ollama
COPY --chmod=755 common/mesa-ollama-start.sh /usr/local/bin/mesa-ollama-start
COPY --chmod=755 common/mesa-gpu-entrypoint.sh /usr/local/bin/mesa-gpu-entrypoint
COPY --chmod=755 common/mesa-gpu-check.sh /usr/local/bin/mesa-gpu-check
COPY --chmod=755 common/ollama-setup.sh /usr/local/bin/ollama-setup
COPY --chmod=755 common/motd-gpu.sh /etc/mesa/motd-gpu.sh
# Non-login interactive shells (docker exec / kubectl exec `bash -i`) do not descend
# from the entrypoint: give them the same CUDA forward-compat env. vnc_startup.sh
# sources ~/.bashrc, not /etc/bash.bashrc, so the desktop start is unaffected.
RUN mv /etc/motd /etc/mesa/motd-base && \
    printf '#!/bin/bash\n/etc/mesa/motd-base\n/etc/mesa/motd-gpu.sh\n' > /etc/motd && chmod 755 /etc/motd && \
    printf '\n# MESA GPU: CUDA forward-compat env for shells not started by the IDE (docker/kubectl exec)\nif [ -r /etc/profile.d/mesa-gpu-env.sh ]; then . /etc/profile.d/mesa-gpu-env.sh; fi\n' >> /etc/bash.bashrc

# KASM desktop GPU wiring: session GL mode hook, GL/VirtualGL/Vulkan diagnostics,
# VirtualGL launcher and menu entries (Applications > System / Graphics)
COPY --chmod=755 gpu-entrypoint.d/ /etc/mesa/gpu-entrypoint.d/
COPY --chmod=755 gpu-check.d/ /etc/mesa/gpu-check.d/
COPY --chmod=755 mesa-gl-run.sh /usr/local/bin/mesa-gl-run
COPY --chmod=644 applications/*.desktop /usr/share/applications/
# Vulkan ICD: the container toolkit injects the NVIDIA libraries but no ICD JSON,
# so without it Vulkan sees only llvmpipe. libEGL_nvidia (not libGLX_nvidia)
# needs no X client libraries. The EGL vendor file ships with the Kasm base;
# recreate it only if a future base drops it.
COPY --chmod=644 nvidia_icd.json /etc/vulkan/icd.d/nvidia_icd.json
RUN test -e /usr/share/glvnd/egl_vendor.d/10_nvidia.json || \
    printf '{"file_format_version":"1.0.0","ICD":{"library_path":"libEGL_nvidia.so.0"}}\n' \
        > /usr/share/glvnd/egl_vendor.d/10_nvidia.json

# vnc_startup.sh sources ~/.bashrc under `set -e`, then hashes the VNC password
# with `python3 -c "import crypt"`: pin that to the system Python 3.12 so a conda
# Python >= 3.13 (no crypt module) earlier on PATH can never abort the desktop.
# conda.sh is loaded in if/fi form (a bare `[ -f ] && .` returns 1 under set -e);
# it only defines `conda` and adds condabin, it activates nothing.
RUN sed -i 's|\$(python3 -c "import crypt|$(/usr/bin/python3 -c "import crypt|g' /dockerstartup/vnc_startup.sh && \
    grep -q '/usr/bin/python3 -c "import crypt' /dockerstartup/vnc_startup.sh && \
    ! grep -q '(python3 -c "import crypt' /dockerstartup/vnc_startup.sh && \
    printf '\n# MESA GPU: `conda activate pytorch` (CUDA PyTorch). if/fi form: vnc_startup.sh sources this file under set -e\nif [ -f /opt/conda/etc/profile.d/conda.sh ]; then . /opt/conda/etc/profile.d/conda.sh; fi\n' \
        >> /home/kasm-user/.bashrc && \
    chown 1000:1000 /home/kasm-user/.bashrc

# Register the local Ollama server with OpenCode (provider `ollama`) and Codex
# (`codex --oss`); the files keep their kasm-user ownership
RUN --mount=type=bind,source=common/patch-agent-configs.py,target=/tmp/patch-agent-configs.py \
    python3 /tmp/patch-agent-configs.py \
        --opencode /home/kasm-user/.config/opencode/opencode.json \
        --codex /home/kasm-user/.codex/config.toml

# NVIDIA_VISIBLE_DEVICES is intentionally NOT set: the k8s device plugin (or
# docker --gpus) sets it; baking `all` would expose every GPU on a node to pods
# that did not request one.
# NVIDIA_DRIVER_CAPABILITIES=all: `graphics` injects the EGL/GLX/Vulkan libraries,
# `video` NVENC/NVDEC (compute,utility alone gives the desktop no GPU GL at all).
# VGL_DISPLAY=egl: VirtualGL's EGL back end on the first NVIDIA device, no X server
# or /dev/dri needed. LD_LIBRARY_PATH drops the Kasm base's leading
# /usr/lib/x86_64-linux-gnu, which makes pip/conda Qt6 wheels (PyQt6, napari)
# load the system Qt6 and crash. Never set __EGL_VENDOR_LIBRARY_FILENAMES (breaks
# EGL on CPU-only runs), HW3D, KASM_EGL_CARD or KASM_RENDERD (no /dev/dri on VICE).
ENV NVIDIA_DRIVER_CAPABILITIES=all \
    VGL_DISPLAY=egl \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64 \
    MESA_TORCH_PYTHON=/opt/conda/envs/pytorch/bin/python \
    OLLAMA_HOST=127.0.0.1:11434 OLLAMA_CONTEXT_LENGTH=32768 OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 \
    OLLAMA_KEEP_ALIVE=5m OLLAMA_NUM_PARALLEL=1 OLLAMA_MAX_LOADED_MODELS=1 CUDA_CACHE_MAXSIZE=1073741824
# KasmVNC NVENC desktop streaming (-videoCodec auto) needs a KasmVNC >= 1.5 base
# (kasmweb/*:1.19.0-rolling-*); the 1.17.0 base's Xvnc 1.3.4 rejects the option
# and the desktop would not start. Future work: see ../README.md.

USER kasm-user
WORKDIR /home/kasm-user/data-store

ENTRYPOINT [ "/usr/local/bin/mesa-gpu-entrypoint", "/dockerstartup/vnc_startup.sh" ]
