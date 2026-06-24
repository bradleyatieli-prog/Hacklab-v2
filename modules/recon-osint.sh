#!/data/data/com.termux/files/usr/bin/bash
# DESC: OSINT & recon (theHarvester, whois, dns enumeration)
source "$HACKLAB_HOME/lib/common.sh"
case "$1" in
  install)
    install_pkg_quiet python
    install_pkg_quiet whois
    install_pkg_quiet dnsutils
    pip install theHarvester 2>/dev/null || warn "theHarvester pip install failed — check network"
    ok "recon-osint ready"
    ;;
  next_steps)
    cat << EOF
Tools ready: whois, dnsutils, and theHarvester (if the pip install above succeeded).
Select recon-osint again any time to drop into a shell with them ready.
EOF
    ;;
  run) bash ;;
esac
