#!/data/data/com.termux/files/usr/bin/bash
# DESC: Reverse engineering (radare2, apktool — apktool useful for Android APK analysis)
source "$HACKLAB_HOME/lib/common.sh"
case "$1" in
  install)
    install_pkg_quiet radare2
    install_pkg_quiet apktool
    ok "reverse-eng ready"
    ;;
  run) bash ;;
esac
