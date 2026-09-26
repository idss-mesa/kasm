# shellcheck shell=bash
# /etc/mesa/gpu-entrypoint.d/20-kasm-gl.sh — KASM desktop OpenGL wiring.
# Sourced (bash) by mesa-gpu-entrypoint just before it execs
# /dockerstartup/vnc_startup.sh, so KasmVNC, the XFCE session and every app
# started from it inherit these variables. Must never exit or fail.
#
# VICE pods get /dev/nvidia* from the NVIDIA device plugin but no /dev/dri, so
# KasmVNC's -hw3d (DRI3) is impossible; GL goes through NVIDIA's GLX/EGL
# userspace instead:
#   MESA_GL_MODE=auto (default)  nvidia when /dev/nvidiactl, libGLX_nvidia and
#                                libEGL_nvidia are present, else mesa
#   MESA_GL_MODE=nvidia          __GLX_VENDOR_LIBRARY_NAME=nvidia: GLX apps in the
#                                session (Chrome, VS Code, Qt, Blender) render on the GPU
#   MESA_GL_MODE=mesa            Mesa llvmpipe by default (escape hatch); heavy 3D
#                                apps can still use the GPU through `mesa-gl-run`
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -un 2>/dev/null || id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null && chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null

_mesa_gl_mode=${MESA_GL_MODE:-auto}
if [ "$_mesa_gl_mode" = auto ]; then
    _mesa_gl_mode=mesa
    if [ -e /dev/nvidiactl ]; then
        _mesa_ldcache=$(ldconfig -p 2>/dev/null)
        case "$_mesa_ldcache" in
            *libGLX_nvidia.so.0*)
                case "$_mesa_ldcache" in *libEGL_nvidia.so.0*) _mesa_gl_mode=nvidia ;; esac ;;
        esac
        unset _mesa_ldcache
    fi
fi
case "$_mesa_gl_mode" in
    nvidia) export __GLX_VENDOR_LIBRARY_NAME=nvidia ;;
    *)      unset __GLX_VENDOR_LIBRARY_NAME ;;
esac
export MESA_GL_MODE_EFFECTIVE="$_mesa_gl_mode"
echo "[mesa-gpu] GL mode: $_mesa_gl_mode (VGL_DISPLAY=${VGL_DISPLAY:-unset}, NVIDIA_DRIVER_CAPABILITIES=${NVIDIA_DRIVER_CAPABILITIES:-unset}, CUDA forward-compat=${MESA_CUDA_COMPAT:-0})"
unset _mesa_gl_mode

# KasmVNC -hw3d without a DRI render node kills Xvnc ("Failed to create gbm")
[ -e "${DRINODE:-/dev/dri/renderD128}" ] || unset HW3D
