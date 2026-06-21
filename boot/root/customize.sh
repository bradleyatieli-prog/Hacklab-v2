# Runs ONCE at module install time inside Magisk's installer.
# Sets up the Alpine rootfs AND copies the project's service graph
# into it, so service.sh just has to chroot in and run the engine.

ROOTFS_DIR=/data/hacklab-rootfs
PROJECT_DIR=/data/hacklab-rootfs/opt/hacklab
ALPINE_VERSION=3.20
ALPINE_ARCH=aarch64
MINIROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ALPINE_ARCH}/alpine-minirootfs-${ALPINE_VERSION}.0-${ALPINE_ARCH}.tar.gz"

ui_print "- Setting up Alpine rootfs at $ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"

if command -v curl >/dev/null 2>&1; then
    curl -L -o /data/local/tmp/alpine-minirootfs.tar.gz "$MINIROOTFS_URL"
    tar -xzf /data/local/tmp/alpine-minirootfs.tar.gz -C "$ROOTFS_DIR"
    rm -f /data/local/tmp/alpine-minirootfs.tar.gz
    ui_print "- Alpine minirootfs extracted"
else
    ui_print "! curl unavailable during install — extract rootfs manually before first boot"
fi

ui_print "- Copying hacklab service graph into rootfs"
mkdir -p "$PROJECT_DIR"
# $MODPATH is set by Magisk to this module's own staged files during install —
# lib/, services/, bin/ ship inside the flashed zip alongside module.prop.
cp -r "$MODPATH/hacklab-src/." "$PROJECT_DIR/" 2>/dev/null

mkdir -p "$ROOTFS_DIR/usr/local/bin"
ln -sf /opt/hacklab/bin/hacklab "$ROOTFS_DIR/usr/local/bin/hacklab" 2>/dev/null
chmod +x "$PROJECT_DIR/bin/hacklab" 2>/dev/null

chmod -R 755 "$ROOTFS_DIR"
ui_print "- Note: tmux/gum/fzf (interactive menu+dashboard) are meant to be run"
ui_print "  from a Termux session attached over SSH (dropbear, port 8022), not"
ui_print "  inside this headless chroot — apk's package set differs from Termux's."
ui_print "- Once SSH'd in, run 'hacklab' — it detects the chroot and adapts."
