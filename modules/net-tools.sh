#!/data/data/com.termux/files/usr/bin/bash
# DESC: Network recon (nmap, netcat, traceroute, mtr) — parallelism tuned to CPU
source "$HACKLAB_HOME/lib/common.sh"
[ -f "$HACKLAB_HOME/lib/hw.sh" ] && source "$HACKLAB_HOME/lib/hw.sh"
case "$1" in
  install)
    install_pkg_quiet nmap
    install_pkg_quiet net-tools
    install_pkg_quiet traceroute
    install_pkg_quiet mtr
    ok "net-tools ready"
    ;;
  next_steps)
    cat << EOF
Tools ready: nmap, net-tools, traceroute, mtr.
Select net-tools again any time to drop into a shell with them on PATH.
$(has_root && echo "Root detected — SYN scans / OS fingerprinting available (nmap -sS -O)." || echo "No root — raw sockets unavailable, use nmap -sT (connect scan) only.")
EOF
    ;;
  run)
    if has_root; then
      log "Root detected — SYN scans / OS fingerprinting available (nmap -sS -O)."
    else
      warn "No root — raw sockets unavailable. Use nmap -sT (connect scan) only."
    fi
    if command -v nmap >/dev/null 2>&1 && type hw_best_nmap_args >/dev/null 2>&1; then
        eval "$(hw_best_nmap_args)"
        export HW_NMAP_ARGS
        log "recommended flags for this device's CPU: ${HW_NMAP_ARGS}"
        log "example: nmap -sT \$HW_NMAP_ARGS <target>"
    fi
    bash
    ;;
esac
