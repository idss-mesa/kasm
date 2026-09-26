#!/bin/bash
# /usr/local/bin/mesa-gl-run <command> [args...]
# Run an OpenGL application through VirtualGL's EGL back end on the NVIDIA GPU
# when one is present (works with only /dev/nvidia*, no /dev/dri); otherwise run
# it unchanged (Mesa llvmpipe). Use it for heavy 3D apps (Blender, ParaView,
# napari 3D, glxspheres): VirtualGL renders off-screen and has the best
# throughput at large window sizes. The session default (NVIDIA GLX vendor
# library, see /etc/mesa/gpu-entrypoint.d/20-kasm-gl.sh) covers everything else.
VGLRUN=/opt/VirtualGL/bin/vglrun
if [ -x "$VGLRUN" ] && [ -e /dev/nvidiactl ] && ldconfig -p 2>/dev/null | grep -q 'libEGL_nvidia.so.0'; then
    # Chrome/Chromium >= 129 and CEF apps need VirtualGL >= 3.1.4 with VGL_CHROMEHACK=1 + --in-process-gpu
    case "$(basename "$1")" in
        google-chrome*|chrome|chromium*) export VGL_CHROMEHACK=1; set -- "$@" --in-process-gpu ;;
    esac
    exec "$VGLRUN" -d "${VGL_DISPLAY:-egl}" "$@"
fi
exec "$@"
