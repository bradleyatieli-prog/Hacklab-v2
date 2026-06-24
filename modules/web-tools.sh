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
  next_steps)
    cat << EOF
Tools ready: sqlmap, nikto.
Select web-tools again any time to drop into a shell with them ready.
EOF
    ;;
  run) bash ;;
esac
