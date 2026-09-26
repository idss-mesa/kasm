# shellcheck shell=bash
# /etc/mesa/gpu-check.d/50-kasm-gl.sh — KASM desktop graphics checks.
# Sourced by mesa-gpu-check (bash, `set -u`) after its driver / CUDA / PyTorch /
# Ollama checks; uses its ok/bad/warn/info/hdr helpers. VICE pods get /dev/nvidia*
# but no /dev/dri, so desktop GL reaches the GPU through NVIDIA's GLX vendor
# library (session default, MESA_GL_MODE) or VirtualGL's EGL back end
# (mesa-gl-run / vglrun -d egl). Run it from a desktop terminal (or with the
# session's environment) so the "session default GL" check sees what apps see.
_kgl_gpu=0
[ -e /dev/nvidiactl ] && nvidia-smi -L >/dev/null 2>&1 && _kgl_gpu=1
_kgl_dpy=${DISPLAY:-:1}
_kgl_vgl=${VGL_DISPLAY:-egl}
_kgl_mode=${MESA_GL_MODE_EFFECTIVE:-unknown}
_kgl_vglrun=/opt/VirtualGL/bin/vglrun
# [launcher...] glxinfo -B on the desktop display -> "vendor|renderer"
_kgl_glx() { DISPLAY=$_kgl_dpy "$@" glxinfo -B 2>/dev/null | awk -F': ' '/OpenGL vendor string/{v=$2} /OpenGL renderer string/{r=$2} END{print v "|" r}'; }

hdr "Desktop graphics libraries (NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES:-unset})"
if [ -d /dev/dri ]; then
    info "/dev/dri present: $(ls /dev/dri | tr '\n' ' ')(unusual on VICE)"
else
    info "no /dev/dri (expected on VICE): KasmVNC -hw3d is unusable, GL uses NVIDIA GLX / VirtualGL EGL"
fi
if [ "$_kgl_gpu" = 1 ]; then
    for _kgl_lib in libEGL_nvidia.so.0 libGLX_nvidia.so.0 libnvidia-encode.so.1 libnvcuvid.so.1 libnvoptix.so.1; do
        if ldconfig -p 2>/dev/null | grep -qF "$_kgl_lib ("; then
            ok "$_kgl_lib injected"
        else
            case "$_kgl_lib" in
                libEGL_nvidia*|libGLX_nvidia*) bad "$_kgl_lib missing: NVIDIA_DRIVER_CAPABILITIES needs 'graphics' (the image sets 'all')" ;;
                *) warn "$_kgl_lib missing (needs the 'video'/'graphics' capability; not every GPU has NVENC)" ;;
            esac
        fi
    done
fi
if grep -qE '^[[:space:]]*hw3d:[[:space:]]*true' /usr/share/kasmvnc/kasmvnc_defaults.yaml /etc/kasmvnc/kasmvnc.yaml "$HOME/.vnc/kasmvnc.yaml" 2>/dev/null \
    && [ ! -e "${DRINODE:-/dev/dri/renderD128}" ]; then
    bad "KasmVNC hw3d: true without ${DRINODE:-/dev/dri/renderD128}: Xvnc dies with 'Failed to create gbm'"
fi
if grep -qs 'Failed to create gbm' "$HOME"/.vnc/*.log; then
    bad "KasmVNC log: 'Failed to create gbm' (hw3d/HW3D enabled without /dev/dri)"
fi

hdr "EGL devices (VirtualGL back end, VGL_DISPLAY=$_kgl_vgl)"
if [ -x /opt/VirtualGL/bin/eglinfo ]; then
    /opt/VirtualGL/bin/eglinfo -e 2>&1 | sed 's/^/  /'
    _kgl_egl=$(/opt/VirtualGL/bin/eglinfo "$_kgl_vgl" 2>/dev/null | awk -F': ' '/EGL vendor string/{print $2; exit}')
    if [ "$_kgl_egl" = NVIDIA ]; then
        ok "VGL_DISPLAY=$_kgl_vgl -> EGL vendor NVIDIA"
    elif [ "$_kgl_gpu" = 1 ]; then
        bad "VGL_DISPLAY=$_kgl_vgl -> EGL vendor '${_kgl_egl:-none}' (expected NVIDIA)"
    else
        info "VGL_DISPLAY=$_kgl_vgl -> EGL vendor '${_kgl_egl:-none}' (no GPU: VirtualGL falls back to Mesa)"
    fi
else
    bad "VirtualGL is not installed (/opt/VirtualGL)"
fi

hdr "OpenGL in the desktop (DISPLAY=$_kgl_dpy, session GL mode ${_kgl_mode})"
if DISPLAY=$_kgl_dpy xdpyinfo >/dev/null 2>&1; then
    _kgl_plain=$(_kgl_glx)
    info "plain GLX (__GLX_VENDOR_LIBRARY_NAME=${__GLX_VENDOR_LIBRARY_NAME:-unset}): ${_kgl_plain#*|}"
    case "$_kgl_gpu:$_kgl_mode:${_kgl_plain%%|*}" in
        1:*:NVIDIA*) ok "session default GL is on the GPU: ${_kgl_plain#*|}" ;;
        1:nvidia:*)  bad "session GL mode is nvidia but plain GLX renders on '${_kgl_plain#*|}'" ;;
        1:mesa:*)    warn "session default GL is software (MESA_GL_MODE=mesa); 3D apps: mesa-gl-run <app>" ;;
        1:*)         warn "default GL here is '${_kgl_plain#*|}': run mesa-gpu-check from a desktop terminal to see the session's GL" ;;
        0:*:Mesa*)   ok "no GPU: desktop GL falls back to Mesa (${_kgl_plain#*|})" ;;
        *)           bad "plain GLX failed on $_kgl_dpy: '${_kgl_plain#*|}'" ;;
    esac
    _kgl_v=$(_kgl_glx "$_kgl_vglrun" -d "$_kgl_vgl")
    case "$_kgl_gpu:${_kgl_v%%|*}" in
        1:NVIDIA*) ok "vglrun -d $_kgl_vgl glxinfo -> ${_kgl_v#*|}" ;;
        1:*)       bad "vglrun -d $_kgl_vgl glxinfo -> '${_kgl_v#*|}' (expected the NVIDIA GPU)" ;;
        *)         info "vglrun -d $_kgl_vgl glxinfo -> '${_kgl_v#*|}'" ;;
    esac
    if [ "$_kgl_gpu" = 1 ]; then
        _kgl_fps=$(DISPLAY=$_kgl_dpy timeout 25 "$_kgl_vglrun" -d "$_kgl_vgl" /opt/VirtualGL/bin/glxspheres64 -f 400 -bt 1 2>/dev/null | awk '/frames\/sec/{f=$1} END{print f}')
        [ -n "$_kgl_fps" ] && info "glxspheres64 through VirtualGL: ${_kgl_fps%.*} frames/s"
    fi
else
    warn "no X display at $_kgl_dpy (run mesa-gpu-check inside the desktop to test GLX)"
fi

hdr "Vulkan (headless; ICD /etc/vulkan/icd.d/nvidia_icd.json)"
if command -v vulkaninfo >/dev/null 2>&1; then
    _kgl_vk=$(env -u DISPLAY timeout 30 vulkaninfo --summary 2>/dev/null | awk -F'= ' '/deviceName/{d=$2} /driverName/{print d " (" $2 ")"}' | paste -sd ';' -)
    case "$_kgl_gpu:$_kgl_vk" in
        1:*"(NVIDIA)"*) ok "Vulkan devices: $_kgl_vk" ;;
        1:*)            bad "Vulkan sees no NVIDIA device: '${_kgl_vk:-nothing}' (ICD /etc/vulkan/icd.d/nvidia_icd.json, 'graphics' capability)" ;;
        *)              info "Vulkan devices: ${_kgl_vk:-none}" ;;
    esac
else
    warn "vulkaninfo not installed"
fi
unset -f _kgl_glx
unset _kgl_gpu _kgl_dpy _kgl_vgl _kgl_mode _kgl_vglrun _kgl_lib _kgl_egl _kgl_plain _kgl_v _kgl_fps _kgl_vk
