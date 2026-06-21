#!/data/data/com.termux/files/usr/bin/bash
# DESC: Wireless auditing (aircrack-ng) — monitor mode usually unsupported
source "$HACKLAB_HOME/lib/common.sh"
[ -f "$HACKLAB_HOME/lib/hw.sh" ] && source "$HACKLAB_HOME/lib/hw.sh"
case "$1" in
  install)
    install_pkg_quiet aircrack-ng
    warn "Installed — but most Android Wi-Fi firmware blocks monitor mode entirely."
    warn "Packet injection / deauth will likely fail regardless of root. This is"
    warn "a chipset/firmware limitation, not something this script can patch around."
    ok "wireless-tools ready (capability not guaranteed)"
    ;;
  run)
    type hw_apply_cpu_governor >/dev/null 2>&1 && hw_apply_cpu_governor performance >/dev/null 2>&1
    [ -n "${HW_OMP_THREADS:-}" ] && log "handshake cracking (aircrack-ng -w) is CPU-bound — OMP_NUM_THREADS=${HW_OMP_THREADS} already exported"
    bash
    ;;
esac
