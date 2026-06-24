#!/data/data/com.termux/files/usr/bin/bash
# DESC: Password auditing (hydra, john, hashcat) — GPU-accelerated when available
source "$HACKLAB_HOME/lib/common.sh"
[ -f "$HACKLAB_HOME/lib/hw.sh" ] && source "$HACKLAB_HOME/lib/hw.sh"
case "$1" in
  install)
    install_pkg_quiet hydra
    install_pkg_quiet john
    if [ "${HW_GPU_OPENCL:-0}" = 1 ]; then
        log "OpenCL detected (${HW_GPU_MODEL:-unknown GPU}) — installing hashcat for GPU cracking"
        install_pkg_quiet clinfo
        install_pkg_quiet hashcat
    else
        log "no OpenCL detected — hydra/john (CPU) only; hashcat would fall back to CPU anyway"
    fi
    ok "password-tools ready"
    ;;
  next_steps)
    if [ "${HW_GPU_OPENCL:-0}" = 1 ]; then
        gpu_note="hydra, john, and hashcat (GPU-accelerated via OpenCL) are ready."
    else
        gpu_note="hydra and john (CPU) are ready — no OpenCL detected, hashcat would fall back to CPU anyway so it wasn't installed."
    fi
    cat << EOF
$gpu_note
Select password-tools again any time to drop into a shell with hardware-tuned flags already exported.
EOF
    ;;
  run)
    if type hw_print_summary >/dev/null 2>&1; then
        hw_print_summary
    fi
    if command -v hashcat >/dev/null 2>&1 && type hw_best_hashcat_args >/dev/null 2>&1; then
        eval "$(hw_best_hashcat_args)"
        export HW_HC_ARGS
        log "hashcat available — recommended flags for this device: ${HW_HC_ARGS}"
        log "example: hashcat -m 0 hash.txt wordlist.txt \$HW_HC_ARGS"
    fi
    bash
    ;;
esac
