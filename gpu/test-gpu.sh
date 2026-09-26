#!/usr/bin/env bash
# gpu/test-gpu.sh IMAGE — smoke test for the MESA KASM desktop NVIDIA GPU image.
#
# Needs an NVIDIA GPU and nvidia-container-toolkit (docker run --gpus).
#   GPU=<index>|all   device to test on (default 0)
#   TIMEOUT=<s>       max wait for the desktop to answer (default 300)
#
#   T1 static     nvidia-smi works; libcuda.so.1 is the HOST driver (no driver
#                 userspace baked); no /usr/local/cuda/compat; vnc_startup.sh
#                 hashes the VNC password with the system python3; the menu
#                 launchers pass desktop-file-validate; every MESA file is
#                 readable (scripts executable) by uid 1000; the apt pin
#                 /etc/apt/preferences.d/mesa-no-nvidia-driver is 644 and, after
#                 `apt-get update` (SKIP if it fetched no package lists, i.e. no
#                 network), leaves the driver packages with no install candidate
#                 but not the CUDA toolkit
#   T2 start      VICE-like start (--user 1000, IPLANT_USER, default entrypoint):
#                 KasmVNC answers on 6901 and, 45 s after start, Xvnc and XFCE are
#                 still up with no 'Failed to create gbm'
#   T3 gpu-check  `mesa-gpu-check --ollama` in the desktop session's environment
#                 exits 0 (driver, CUDA/compat, PyTorch, Ollama 100% GPU, GL, Vulkan)
#   T4 desktop    VirtualGL EGL GLX, the session's default GLX and Vulkan all render
#                 on the allocated GPU; __GLX_VENDOR_LIBRARY_NAME=mesa moves one app
#                 to llvmpipe; shells see conda, the system python3 and nvitop;
#                 a `docker exec ... bash -i` shell gets the session's CUDA
#                 forward-compat state, and `set -e; . ~/.bashrc` still succeeds
#   T5 no-GPU     without a GPU the desktop still starts (GL mode mesa, llvmpipe)
#                 and mesa-gpu-check reports the missing GPU (non-zero) cleanly
#
# Exits non-zero if any test fails. Containers are always removed.
set -uo pipefail

IMAGE=${1:?usage: GPU=<index|all> gpu/test-gpu.sh IMAGE}
GPU=${GPU:-0}
TIMEOUT=${TIMEOUT:-300}
APP_PORT=6901
SETTLE=45
VNC_PW="mesa-test-$RANDOM$RANDOM"
if [ "$GPU" = all ]; then GPUS=all; else GPUS="device=$GPU"; fi
PFX="mesa-gpu-kasm-test-$$"
LOGDIR=$(mktemp -d "${TMPDIR:-/tmp}/mesa-gpu-kasm-test.XXXXXX")

CONTAINERS=()
cleanup() {
    for c in "${CONTAINERS[@]}"; do docker rm -f "$c" >/dev/null 2>&1; done
}
trap cleanup EXIT
trap 'exit 130' INT TERM

NAMES=() STATES=() DETAILS=()
FAILED=0
record() { # name PASS|FAIL|SKIP detail (SKIP: could not run here, e.g. no network)
    NAMES+=("$1"); STATES+=("$2"); DETAILS+=("$3")
    case "$2" in PASS|SKIP) ;; *) FAILED=$((FAILED + 1)) ;; esac
    printf '[%s] %s: %s\n' "$2" "$1" "$3"
}
say() { printf '\n\e[1m== %s\e[0m\n' "$*"; }

start_desktop() { # name [docker run args...]
    local name=$1; shift
    CONTAINERS+=("$name")
    docker run -d --name "$name" --user 1000 --shm-size=1g \
        -e VNC_PW="$VNC_PW" -e IPLANT_USER=mesa-test -p "127.0.0.1::$APP_PORT" "$@" "$IMAGE" >/dev/null
}

# wait until KasmVNC answers over HTTPS (self-signed cert) -> prints the status code
wait_web() { # name
    local name=$1 port code="000" t0=$SECONDS
    port=$(docker port "$name" "$APP_PORT/tcp" | head -1 | awk -F: '{print $NF}')
    while [ $((SECONDS - t0)) -lt "$TIMEOUT" ]; do
        [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = true ] || { echo "exited"; return 1; }
        code=$(curl -ks -m 5 -o /dev/null -w '%{http_code}' "https://127.0.0.1:$port/")
        case "$code" in 200|401) echo "$code after $((SECONDS - t0)) s"; return 0 ;; esac
        sleep 3
    done
    echo "no answer within ${TIMEOUT} s (last https code $code)"
    return 1
}

# the desktop must still be up SETTLE seconds after start, with no DRI3/gbm abort
desktop_alive() { # name started_at
    local name=$1 started=$2 gbm
    while [ $((SECONDS - started)) -lt "$SETTLE" ]; do sleep 2; done
    [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = true ] || { echo "container exited"; return 1; }
    docker exec "$name" pgrep -x Xvnc >/dev/null || { echo "Xvnc not running"; return 1; }
    docker exec "$name" pgrep -x xfce4-session >/dev/null || { echo "xfce4-session not running"; return 1; }
    gbm=$( { docker logs "$name" 2>&1; docker exec "$name" sh -c 'cat "$HOME"/.vnc/*.log 2>/dev/null'; } | grep -c 'Failed to create gbm')
    [ "$gbm" = 0 ] || { echo "'Failed to create gbm' in the logs"; return 1; }
    echo "Xvnc + xfce4-session up after ${SETTLE} s, no 'Failed to create gbm'"
}

# run a bash snippet inside the container with the XFCE session's GL/runtime env
session_exec() { # name script
    docker exec -u 1000 -e DISPLAY=:1 "$1" bash -c '
        pid=$(pgrep -x xfce4-session | head -1)
        [ -n "$pid" ] || { echo "no xfce4-session process" >&2; exit 90; }
        while IFS= read -r -d "" kv; do
            case "$kv" in
                __GLX_VENDOR_LIBRARY_NAME=*|MESA_GL_MODE_EFFECTIVE=*|XDG_RUNTIME_DIR=*|LD_LIBRARY_PATH=*) export "$kv" ;;
            esac
        done < "/proc/$pid/environ"
        '"$2"
}

renderer() { awk -F': ' '/OpenGL renderer string/{print $2; exit}'; }

echo "Image: $IMAGE   GPU: $GPUS   logs: $LOGDIR"
docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "image $IMAGE not found (make build-gpu)" >&2; exit 2; }

# ---------------------------------------------------------------- T1 static
say "T1 static: host driver injected, nothing baked"
if out=$(docker run --rm -i --user 1000 --gpus "$GPUS" --entrypoint bash "$IMAGE" -s 2>&1 <<'EOF'
set -u
nvidia-smi -L || { echo "nvidia-smi failed"; exit 11; }
drv=$(sed -nE 's/.*Kernel Module( for [a-z0-9_]+)?[[:space:]]+([0-9]+\.[0-9.]+).*/\2/p' /proc/driver/nvidia/version | head -1)
lib=$(readlink -f "$(ldconfig -p | awk '/libcuda\.so\.1 /{print $NF; exit}')")
echo "host driver ${drv:-?}; libcuda.so.1 -> $lib"
case "$lib" in */libcuda.so."$drv") ;; *) echo "libcuda.so.1 is not the host driver's"; exit 12 ;; esac
if dpkg -l | grep -E '^ii +(nvidia-driver|nvidia-dkms|nvidia-utils|nvidia-compute-utils|libnvidia-(compute|gl|decode|encode|extra|fbc1|cfg1|common)|cuda-drivers)'; then echo "driver packages baked"; exit 13; fi
[ ! -e /usr/local/cuda/compat ] || { echo "/usr/local/cuda/compat exists (toolkit would force compat)"; exit 14; }
grep -q '$(/usr/bin/python3 -c "import crypt' /dockerstartup/vnc_startup.sh || { echo "vnc_startup.sh does not use /usr/bin/python3"; exit 15; }
if command -v desktop-file-validate >/dev/null; then
    for f in /usr/share/applications/mesa-*.desktop; do
        desktop-file-validate "$f" || { echo "invalid launcher $f"; exit 16; }
    done
fi
# modes must not depend on the builder's umask / checkout permissions: as uid 1000
[ "$(id -u)" = 1000 ] || { echo "static checks must run as uid 1000, not $(id -u)"; exit 17; }
for f in /etc/profile.d/mesa-gpu-env.sh /etc/apt/preferences.d/mesa-no-nvidia-driver \
         /etc/vulkan/icd.d/nvidia_icd.json /usr/share/applications/mesa-*.desktop \
         /etc/mesa/gpu-entrypoint.d/*.sh /etc/mesa/gpu-check.d/*.sh; do
    [ -f "$f" ] && [ -r "$f" ] || { echo "not readable by uid 1000: $(stat -c '%a %U %n' "$f" 2>&1)"; exit 18; }
done
for f in /usr/local/bin/cuda-probe /usr/local/bin/ollama /usr/local/bin/ollama.bin /usr/local/bin/mesa-ollama-start \
         /usr/local/bin/mesa-gpu-entrypoint /usr/local/bin/mesa-gpu-check /usr/local/bin/ollama-setup \
         /usr/local/bin/mesa-gl-run /usr/local/bin/nvitop /etc/mesa/motd-gpu.sh /etc/mesa/motd-base /etc/motd; do
    [ -r "$f" ] && [ -x "$f" ] || { echo "not executable by uid 1000: $(stat -L -c '%a %U %n' "$f" 2>&1)"; exit 19; }
done
for d in /etc/mesa /etc/mesa/gpu-entrypoint.d /etc/mesa/gpu-check.d /usr/share/applications /etc/vulkan/icd.d; do
    [ -r "$d" ] && [ -x "$d" ] || { echo "directory not searchable by uid 1000: $(stat -c '%a %U %n' "$d" 2>&1)"; exit 20; }
done
pin=$(stat -c '%a %U' /etc/apt/preferences.d/mesa-no-nvidia-driver 2>&1)
[ "$pin" = "644 root" ] || { echo "apt pin /etc/apt/preferences.d/mesa-no-nvidia-driver: '$pin', expected '644 root'"; exit 21; }
echo "static ok"
EOF
); then
    record "T1 static" PASS "$(printf '%s' "$out" | grep -E '^host driver' | head -1); MESA files readable by uid 1000; apt pin 644 root"
else
    record "T1 static" FAIL "$(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
fi
# the apt pin in effect: a throwaway root container refreshes the package lists
# (needs network) and asks apt for the driver packages' install candidates.
# apt-get update exits 0 on noble even when every fetch fails, so "no network"
# is detected as "no package lists downloaded" (as in rstudio's test)
pin_out=$(docker run --rm --user 0 --entrypoint bash "$IMAGE" -c '
    rm -rf /var/lib/apt/lists/*
    timeout 300 apt-get update -qq >/dev/null 2>&1
    if ! compgen -G "/var/lib/apt/lists/*_Packages*" >/dev/null; then echo "NO-NETWORK: apt-get update fetched no package lists"; exit 0; fi
    for p in nvidia-driver-580 cuda-drivers libnvidia-compute-580 cuda-toolkit-12-6; do
        printf "== %s\n" "$p"; apt-cache policy "$p"
    done' 2>&1)
printf '%s\n' "$pin_out" > "$LOGDIR/apt-pin.log"
if grep -q '^NO-NETWORK' <<<"$pin_out"; then
    record "T1 apt pin (apt-cache policy)" SKIP "apt-get update fetched no package lists (no network?): pin file checked, candidates not"
else
    # candidate per package; a package must be known (have a version table) for the check to mean anything
    pin_res=$(awk '/^== /{p=$2} /Candidate:/{c[p]=$2} /^ +[*]* *[0-9][^ ]* +-?[0-9]+$/{v[p]++}
        END{for (p in c) printf "%s=%s/%d ", p, c[p], v[p]}' <<<"$pin_out")
    bad_pin=
    for p in nvidia-driver-580 cuda-drivers libnvidia-compute-580; do
        grep -qE "(^| )$p=\(none\)/[1-9]" <<<"$pin_res" || bad_pin+="$p "
    done
    grep -qE '(^| )cuda-toolkit-12-6=[0-9][^/]*/[1-9]' <<<"$pin_res" || bad_pin+="cuda-toolkit-12-6(should stay installable) "
    if [ -z "$bad_pin" ]; then
        record "T1 apt pin (apt-cache policy)" PASS "Candidate: (none) for nvidia-driver-580, cuda-drivers, libnvidia-compute-580; cuda-toolkit-12-6 installable"
    else
        record "T1 apt pin (apt-cache policy)" FAIL "wrong candidate for: $bad_pin($pin_res) see $LOGDIR/apt-pin.log"
    fi
fi
# (captured first: `producer | grep -q` under pipefail fails when grep exits early and the producer gets SIGPIPE)
image_env=$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$IMAGE")
if grep -q '^NVIDIA_VISIBLE_DEVICES=' <<<"$image_env"; then
    record "T1 no baked NVIDIA_VISIBLE_DEVICES" FAIL "image ENV sets NVIDIA_VISIBLE_DEVICES"
fi

# ---------------------------------------------------------------- T2 start
say "T2 start like VICE (--user 1000, --gpus $GPUS) + T5 no-GPU container"
GPU_C="$PFX-gpu"; NOGPU_C="$PFX-nogpu"
start_desktop "$GPU_C" --gpus "$GPUS"; t_gpu=$SECONDS
# NVIDIA_VISIBLE_DEVICES=void: no GPU even where nvidia is the default runtime
start_desktop "$NOGPU_C" -e NVIDIA_VISIBLE_DEVICES=void; t_nogpu=$SECONDS

if web=$(wait_web "$GPU_C"); then
    record "T2 KasmVNC answers (GPU)" PASS "https :$APP_PORT -> $web"
    if alive=$(desktop_alive "$GPU_C" "$t_gpu"); then
        record "T2 desktop stable (GPU)" PASS "$alive"
    else
        record "T2 desktop stable (GPU)" FAIL "$alive"
    fi
else
    record "T2 KasmVNC answers (GPU)" FAIL "$web"
fi
docker logs "$GPU_C" > "$LOGDIR/gpu-container.log" 2>&1

# ---------------------------------------------------------------- T3 gpu-check
say "T3 mesa-gpu-check --ollama (desktop session environment)"
if session_exec "$GPU_C" 'mesa-gpu-check --ollama' > "$LOGDIR/gpu-check.log" 2>&1; then
    record "T3 mesa-gpu-check --ollama" PASS "$(grep -E '== Summary' "$LOGDIR/gpu-check.log" | sed 's/^== //')"
else
    record "T3 mesa-gpu-check --ollama" FAIL "$(grep -E '\[FAIL\]|== Summary' "$LOGDIR/gpu-check.log" | sed 's/\x1b\[[0-9;]*m//g' | tr -s ' ' | tr '\n' ';' | cut -c1-400)"
fi
sed 's/\x1b\[[0-9;]*m//g' "$LOGDIR/gpu-check.log"

# ---------------------------------------------------------------- T4 desktop GPU
say "T4 desktop GL / VirtualGL / Vulkan on the allocated GPU"
gpu_name=$(docker exec "$GPU_C" nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
echo "allocated GPU: ${gpu_name:-?}"
if [ -z "$gpu_name" ]; then
    record "T4 GPU name" FAIL "nvidia-smi inside the desktop container failed"
else
    vgl=$(session_exec "$GPU_C" '/opt/VirtualGL/bin/vglrun -d "${VGL_DISPLAY:-egl}" glxinfo -B' 2>&1 | renderer)
    case "$vgl" in
        *"$gpu_name"*) record "T4a VirtualGL EGL (vglrun glxinfo)" PASS "$vgl" ;;
        *)             record "T4a VirtualGL EGL (vglrun glxinfo)" FAIL "renderer '${vgl:-none}', expected $gpu_name" ;;
    esac
    out=$(session_exec "$GPU_C" 'echo "mode=${MESA_GL_MODE_EFFECTIVE:-unset} vendor=${__GLX_VENDOR_LIBRARY_NAME:-unset}"; glxinfo -B' 2>&1)
    mode=$(printf '%s\n' "$out" | grep -m1 '^mode=')
    plain=$(printf '%s\n' "$out" | renderer)
    case "$mode:$plain" in
        "mode=nvidia vendor=nvidia:"*"$gpu_name"*) record "T4b session GLX (plain glxinfo)" PASS "$plain ($mode)" ;;
        *) record "T4b session GLX (plain glxinfo)" FAIL "renderer '${plain:-none}' ($mode), expected $gpu_name via GL mode nvidia" ;;
    esac
    # the per-app software-GL fallback the README documents
    sw=$(session_exec "$GPU_C" '__GLX_VENDOR_LIBRARY_NAME=mesa glxinfo -B' 2>&1 | renderer)
    case "$sw" in
        llvmpipe*) record "T4e per-app GL fallback" PASS "__GLX_VENDOR_LIBRARY_NAME=mesa -> $sw" ;;
        *)         record "T4e per-app GL fallback" FAIL "__GLX_VENDOR_LIBRARY_NAME=mesa -> '${sw:-none}', expected llvmpipe" ;;
    esac
    vk=$(docker exec "$GPU_C" bash -c 'env -u DISPLAY timeout 60 vulkaninfo --summary 2>/dev/null' | awk -F'= ' '/deviceName/{d=$2} /driverName/{print d " (" $2 ")"}' | paste -sd ';' -)
    case "$vk" in
        *"$gpu_name (NVIDIA)"*) record "T4c Vulkan device" PASS "$vk" ;;
        *)                      record "T4c Vulkan device" FAIL "'${vk:-none}', expected $gpu_name (NVIDIA)" ;;
    esac
fi
# a desktop terminal's bash: conda available (not on PATH), system python3 first,
# nvitop (advertised on the landing panel) on PATH without `conda activate` and
# working in the session env (CUDA compat included), the GPU landing panel shown
shell=$(docker exec -u 1000 "$GPU_C" bash -ic 'echo "conda=$(type -t conda) python3=$(command -v python3) nvitop=$(command -v nvitop)"; conda env list | grep -c "^pytorch "' 2>/dev/null)
nvitop_out=$(session_exec "$GPU_C" 'nvitop -1' 2>&1)
if grep -q 'conda=function python3=/usr/bin/python3 nvitop=/usr/local/bin/nvitop' <<<"$shell" && [ "$(tail -1 <<<"$shell")" = 1 ] \
    && grep -q 'OLLAMA' <<<"$shell" && grep -q 'NVITOP' <<<"$nvitop_out" && grep -qF -- "${gpu_name:-?}" <<<"$nvitop_out"; then
    record "T4d terminal shell" PASS "conda function + env pytorch, python3=/usr/bin/python3, nvitop on PATH and sees ${gpu_name}, GPU landing panel"
else
    record "T4d terminal shell" FAIL "$(printf '%s' "$shell" | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'conda=|OLLAMA|^[0-9]+$' | tr '\n' ' ') nvitop: $(printf '%s' "$nvitop_out" | grep -m1 -E 'NVITOP|rror' | cut -c1-120)"
fi

# a non-login interactive shell that did not descend from the entrypoint
# (docker exec / kubectl exec `bash -i`) gets the session's CUDA forward-compat
# state from /etc/bash.bashrc; vnc_startup.sh's `set -e; source ~/.bashrc` still works
sess_compat=$(docker exec -u 1000 "$GPU_C" bash -c 'pid=$(pgrep -x xfce4-session | head -1); [ -n "$pid" ] && tr "\0" "\n" < "/proc/$pid/environ"' 2>/dev/null | sed -n 's/^MESA_CUDA_COMPAT=/MARK compat=/p' | head -1)
exec_env=$(docker exec -u 1000 "$GPU_C" bash -i -c 'echo "MARK compat=${MESA_CUDA_COMPAT:-unset}"; case ":$LD_LIBRARY_PATH:" in *":$MESA_CUDA_COMPAT_DIR:"*) echo "MARK ldp=compat" ;; *) echo "MARK ldp=host" ;; esac' 2>/dev/null | grep '^MARK ')
exec_compat=$(grep -m1 'compat=' <<<"$exec_env"); exec_ldp=$(grep -m1 'ldp=' <<<"$exec_env")
bashrc_ok=$(docker exec -u 1000 "$GPU_C" bash -c 'set -e; source "$HOME/.bashrc" >/dev/null 2>&1; echo sourced-ok' 2>&1 | tail -1)
case "$sess_compat:$exec_compat:$exec_ldp" in
    "MARK compat=1:MARK compat=1:MARK ldp=compat"|"MARK compat=0:MARK compat=0:MARK ldp=host") exec_state=ok ;;
    *) exec_state=bad ;;
esac
if [ "$exec_state" = ok ] && [ "$bashrc_ok" = sourced-ok ]; then
    record "T4f exec shell CUDA compat" PASS "docker exec bash -i: ${exec_compat#MARK } (${exec_ldp#MARK }) = session ${sess_compat#MARK }; set -e + ~/.bashrc ok"
else
    record "T4f exec shell CUDA compat" FAIL "session '${sess_compat:-none}', docker exec bash -i '${exec_compat:-none}' '${exec_ldp:-none}', set -e ~/.bashrc: '${bashrc_ok:-none}'"
fi

# ---------------------------------------------------------------- T5 no-GPU
say "T5 no GPU: desktop still starts, mesa-gpu-check reports the missing GPU"
if web=$(wait_web "$NOGPU_C"); then
    if alive=$(desktop_alive "$NOGPU_C" "$t_nogpu"); then
        nogpu_logs=$(docker logs "$NOGPU_C" 2>&1)
        if grep -q '\[mesa-gpu\] GL mode: mesa' <<<"$nogpu_logs"; then
            record "T5 desktop without GPU" PASS "https -> $web; GL mode mesa; $alive"
        else
            record "T5 desktop without GPU" FAIL "no '[mesa-gpu] GL mode: mesa' in the logs"
        fi
    else
        record "T5 desktop without GPU" FAIL "$alive"
    fi
    session_exec "$NOGPU_C" 'mesa-gpu-check' > "$LOGDIR/nogpu-check.log" 2>&1
    rc=$?
    clean=$(sed 's/\x1b\[[0-9;]*m//g' "$LOGDIR/nogpu-check.log")
    if [ "$rc" -ne 0 ] && grep -q 'no NVIDIA GPU in this container' <<<"$clean" \
        && grep -q '^== Summary' <<<"$clean" && ! grep -qiE 'unbound variable|syntax error|command not found' <<<"$clean"; then
        record "T5 mesa-gpu-check without GPU" PASS "exit $rc, reports 'no NVIDIA GPU', $(printf '%s' "$clean" | grep '^== Summary' | sed 's/^== //')"
    else
        record "T5 mesa-gpu-check without GPU" FAIL "exit $rc: $(printf '%s' "$clean" | grep -E 'FAIL|Summary|unbound|not found' | tr '\n' ';' | cut -c1-300)"
    fi
    if grep -q 'no GPU: desktop GL falls back to Mesa' <<<"$clean"; then
        record "T5 GL fallback (llvmpipe)" PASS "$(printf '%s' "$clean" | grep -o 'desktop GL falls back to Mesa.*' | head -1)"
    else
        record "T5 GL fallback (llvmpipe)" FAIL "$(printf '%s' "$clean" | grep -E 'plain GLX' | head -2 | tr '\n' ' ')"
    fi
else
    record "T5 desktop without GPU" FAIL "$web"
fi
docker logs "$NOGPU_C" > "$LOGDIR/nogpu-container.log" 2>&1

# ---------------------------------------------------------------- summary
say "Summary ($IMAGE, GPU $GPUS)"
printf '%-6s  %-38s  %s\n' RESULT TEST DETAIL
for i in "${!NAMES[@]}"; do
    printf '%-6s  %-38s  %s\n' "${STATES[$i]}" "${NAMES[$i]}" "${DETAILS[$i]}"
done
echo "logs: $LOGDIR"
if [ "$FAILED" -gt 0 ]; then
    echo "$FAILED test(s) FAILED"
    exit 1
fi
echo "all ${#NAMES[@]} tests passed"
