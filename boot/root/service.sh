#!/system/bin/sh
# ============================================================
#  hacklab-v2 / boot/root/service.sh
#  Magisk late_start service — root, independent of any app.
#  Chroots into the Alpine rootfs and brings the service graph up.
# ============================================================
ROOTFS_DIR=/data/hacklab-rootfs
LOG=/data/hacklab-rootfs/opt/hacklab/boot.log

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 1; done

if [ ! -d "$ROOTFS_DIR/opt/hacklab/lib" ]; then
    log -p w -t hacklab "rootfs/service graph missing — did customize.sh run?"
    exit 1
fi

mount -o bind /dev "$ROOTFS_DIR/dev" 2>/dev/null
mount -t proc proc "$ROOTFS_DIR/proc" 2>/dev/null
mount -t sysfs sysfs "$ROOTFS_DIR/sys" 2>/dev/null

chroot "$ROOTFS_DIR" /bin/sh -c '
    apk add --no-cache bash python3 dropbear curl >/dev/null 2>&1
    export HACKLAB_HOME=/opt/hacklab
    chmod +x "$HACKLAB_HOME/lib/svc-engine.sh"
    bash "$HACKLAB_HOME/lib/svc-engine.sh" up
' >> "$LOG" 2>&1 &
