#!/data/data/com.termux/files/usr/bin/bash
# hacklab-v2 / uninstall.sh
export HACKLAB_HOME="$HOME/.hacklab"
source "$HACKLAB_HOME/lib/common.sh" 2>/dev/null

[ -x "$HACKLAB_HOME/lib/svc-engine.sh" ] && bash "$HACKLAB_HOME/lib/svc-engine.sh" down 2>/dev/null
tmux kill-session -t hacklab 2>/dev/null || true

rm -f "$HOME/.termux/boot/hacklab-boot"
echo "Removed no-root boot trigger (if present)."
echo "If you flashed the root Magisk module, remove it from:"
echo "  Magisk app > Modules > HackLab v2 Core > trash icon > reboot"
echo "(Direct deletion of /data/adb/modules entries while running can leave"
echo " dangling mounts — go through Magisk's UI for a clean removal.)"

read -rp "Delete $HACKLAB_HOME entirely? [y/N] " confirm
if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    rm -rf "$HACKLAB_HOME"
    echo "Removed."
fi
