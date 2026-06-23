#!/data/data/com.termux/files/usr/bin/bash
# DESC: Web app testing (sqlmap, nikto)
source "$HACKLAB_HOME/lib/common.sh"
case "$1" in
  install)
    install_pkg_quiet python
    pip install sqlmap 2>/dev/null || install_pkg_quiet sqlmap
    install_pkg_quiet nikto
    ok "web-tools ready"
    ;;
  run) bash ;;
esac
