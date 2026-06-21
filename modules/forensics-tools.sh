#!/data/data/com.termux/files/usr/bin/bash
# DESC: Forensics (binwalk, exiftool, foremost)
source "$HACKLAB_HOME/lib/common.sh"
case "$1" in
  install)
    install_pkg_quiet binwalk
    install_pkg_quiet exiftool
    install_pkg_quiet foremost
    ok "forensics-tools ready"
    ;;
  run) bash ;;
esac
