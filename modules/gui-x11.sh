#!/data/data/com.termux/files/usr/bin/bash
# DESC: Optional GUI desktop — light style (xfce/lxqt/i3) or a full distro (Kali/Ubuntu/Debian/Arch/Fedora/openSUSE/Alpine) via proot-distro
# ============================================================
#  hacklab-v2 / modules/gui-x11.sh
#
#  Two independent paths, picked once at install time and switchable
#  later without reinstalling anything else:
#
#   "light"  — xfce/lxqt/i3 running directly under Termux's own
#              userland via Termux-X11. Fast, small, no second OS.
#
#   "distro" — a real Linux distro (Kali/Ubuntu/Debian/Arch/Fedora/
#              openSUSE/Alpine) pulled as an OCI image via proot-distro,
#              with a desktop environment installed inside it. Heavier
#              and slower (ptrace-based), but a genuinely complete,
#              unmodified userland — this is how Kali Linux gets in.
#
#  State lives in one file so `run` knows which path is active:
#    $HACKLAB_HOME/gui-x11-state  →  "light:<style>" | "distro:<name>:<style>"
# ============================================================
source "$HACKLAB_HOME/lib/common.sh"
[ -f "$HACKLAB_HOME/lib/hw.sh" ] && source "$HACKLAB_HOME/lib/hw.sh"

STATE_FILE="$HACKLAB_HOME/gui-x11-state"
# Back-compat: the original module only ever wrote this file.
LEGACY_STYLE_FILE="$HACKLAB_HOME/gui-x11-style"

# ── free storage / RAM helpers ──────────────────────────────────
free_mb_home() {
    df -Pk "$HOME" 2>/dev/null | awk 'NR==2{printf "%d", $4/1024}'
}

ram_total_mb() {
    # hw-profile.env (if install.sh's hardware phase has run) is the
    # authoritative source; fall back to /proc/meminfo directly.
    if [ -n "${HW_RAM_TOTAL_MB:-}" ] && [ "${HW_RAM_TOTAL_MB:-0}" -gt 0 ] 2>/dev/null; then
        echo "$HW_RAM_TOTAL_MB"
    else
        awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null || echo 0
    fi
}

# ── top-level path choice ───────────────────────────────────────
pick_path() {
    ensure_gum || true
    local pick=""
    if command -v gum >/dev/null 2>&1; then
        pick="$(printf 'light  — xfce/lxqt/i3 directly over Termux-X11, fastest, smallest\ndistro — a full Linux OS (Kali, Ubuntu, Debian, Arch, Fedora, openSUSE, Alpine) via proot-distro, heavier\n' | \
            gum choose --header "GUI desktop path:")" || true
    else
        {
            echo "Pick a path:"
            echo "  1) light  — xfce/lxqt/i3 directly over Termux-X11 (fastest, smallest)"
            echo "  2) distro — full Linux OS via proot-distro (Kali / Ubuntu / Debian / Arch / Fedora / openSUSE / Alpine)"
        } >&2
        read -rp "> " n
        case "$n" in 1) pick="light" ;; 2) pick="distro" ;; esac
    fi
    case "$pick" in
        light*)  echo "light" ;;
        distro*) echo "distro" ;;
        *) echo "" ;;
    esac
}

# ════════════════════════════════════════════════════════════════
#  LIGHT path — unchanged behavior from the original module
# ════════════════════════════════════════════════════════════════
pick_style() {
    ensure_gum || true
    local pick=""
    if command -v gum >/dev/null 2>&1; then
        pick="$(printf 'xfce  — full desktop, heaviest, most familiar\nlxqt  — full desktop, noticeably lighter than xfce\ni3    — tiling window manager, lightest, keyboard-driven\n' | \
            gum choose --header "desktop style:")" || true
    else
        {
            echo "Pick a style:"
            echo "  1) xfce — full desktop, heaviest, most familiar"
            echo "  2) lxqt — full desktop, noticeably lighter than xfce"
            echo "  3) i3   — tiling window manager, lightest, keyboard-driven"
        } >&2
        read -rp "> " n
        case "$n" in
            1) pick="xfce" ;; 2) pick="lxqt" ;; 3) pick="i3" ;;
        esac
    fi
    case "$pick" in
        xfce*) echo "xfce" ;;
        lxqt*) echo "lxqt" ;;
        i3*)   echo "i3" ;;
        *) echo "" ;;
    esac
}

install_style_light() {
    case "$1" in
        xfce) install_pkg_quiet xfce4 ;;
        lxqt) install_pkg_quiet lxqt ;;
        i3)   install_pkg_quiet i3 && install_pkg_quiet dmenu ;;
        *) err "unknown style '$1'"; return 1 ;;
    esac
}

xstartup_for_light() {
    case "$1" in
        xfce) echo "dbus-launch --exit-with-session xfce4-session" ;;
        lxqt) echo "dbus-launch --exit-with-session startlxqt" ;;
        i3)   echo "dbus-launch --exit-with-session i3" ;;
    esac
}

# ════════════════════════════════════════════════════════════════
#  DISTRO path — proot-distro, OCI image references (v5+ syntax;
#  short "user/repo" or "repo:tag" both resolve against Docker Hub)
# ════════════════════════════════════════════════════════════════

# name → image-ref:tag  (pinned, not ":latest" — proot-distro's own
# docs warn that floating tags can be unstable/bleeding-edge)
distro_image() {
    case "$1" in
        kali)      echo "kalilinux/kali-rolling" ;;
        ubuntu)    echo "ubuntu:24.04" ;;
        debian)    echo "debian:12" ;;
        archlinux) echo "archlinux/archlinux:latest" ;;
        fedora)    echo "fedora:40" ;;
        opensuse)  echo "opensuse/tumbleweed:latest" ;;
        alpine)    echo "alpine:3.20" ;;
        *) echo "" ;;
    esac
}

distro_blurb() {
    case "$1" in
        kali)      echo "Kali Linux  — the curated pentest distro itself; biggest download" ;;
        ubuntu)    echo "Ubuntu      — widest package availability, most tutorials" ;;
        debian)    echo "Debian      — stable, minimal, what Kali is built on" ;;
        archlinux) echo "Arch Linux  — rolling release, smallest base, more setup work" ;;
        fedora)    echo "Fedora      — current upstream packages, dnf" ;;
        opensuse)  echo "openSUSE    — zypper, Tumbleweed rolling" ;;
        alpine)    echo "Alpine      — musl-based, tiny, lightest of the full distros" ;;
    esac
}

ensure_proot_distro() {
    command -v proot-distro >/dev/null 2>&1 && return 0
    install_pkg_quiet proot-distro
    hash -r
    command -v proot-distro >/dev/null 2>&1
}

distro_installed() {
    proot-distro list 2>/dev/null | grep -qiw "$1"
}

pick_distro() {
    ensure_gum || true
    local names=(kali ubuntu debian archlinux fedora opensuse alpine)
    local pick=""
    if command -v gum >/dev/null 2>&1; then
        local lines=""
        for n in "${names[@]}"; do lines+="$(distro_blurb "$n")"$'\n'; done
        pick="$(printf '%s' "$lines" | gum choose --header "which distro?")" || true
    else
        {
            echo "Pick a distro:"
            local i=1
            for n in "${names[@]}"; do echo "  $i) $(distro_blurb "$n")"; i=$((i+1)); done
        } >&2
        read -rp "> " n
        [ "$n" -ge 1 ] 2>/dev/null && [ "$n" -le "${#names[@]}" ] 2>/dev/null && pick="$(distro_blurb "${names[$((n-1))]}")"
    fi
    for n in "${names[@]}"; do
        [[ "$pick" == "$(distro_blurb "$n")"* ]] && { echo "$n"; return; }
    done
    echo ""
}

# package set per (distro family, DE style) — best effort; package
# names drift across releases, this covers the common case and warns
# rather than silently failing on the rest.
de_install_cmd() {
    local distro="$1" style="$2" family=""
    case "$distro" in
        kali|ubuntu|debian) family="apt" ;;
        archlinux)          family="pacman" ;;
        fedora)             family="dnf" ;;
        opensuse)           family="zypper" ;;
        alpine)             family="apk" ;;
    esac
    case "$family:$style" in
        apt:xfce)     echo "apt-get update && apt-get install -y xfce4 dbus-x11" ;;
        apt:lxqt)     echo "apt-get update && apt-get install -y lxqt dbus-x11" ;;
        apt:i3)       echo "apt-get update && apt-get install -y i3 dmenu dbus-x11 xterm" ;;
        pacman:xfce)  echo "pacman -Sy --noconfirm --needed xfce4 dbus" ;;
        pacman:lxqt)  echo "pacman -Sy --noconfirm --needed lxqt dbus sddm" ;;
        pacman:i3)    echo "pacman -Sy --noconfirm --needed i3-wm dmenu dbus xterm" ;;
        dnf:xfce)     echo "dnf install -y xfce4-session xfdesktop xfce4-panel xfce4-terminal dbus-x11" ;;
        dnf:lxqt)     echo "dnf install -y @lxqt-desktop-environment dbus-x11" ;;
        dnf:i3)       echo "dnf install -y i3 dmenu dbus-x11 xterm" ;;
        zypper:xfce)  echo "zypper --non-interactive install -t pattern xfce && zypper --non-interactive install dbus-1-x11" ;;
        zypper:lxqt)  echo "zypper --non-interactive install -t pattern lxqt && zypper --non-interactive install dbus-1-x11" ;;
        zypper:i3)    echo "zypper --non-interactive install i3 dmenu dbus-1-x11 xterm" ;;
        apk:xfce)     echo "apk add --no-cache xfce4 dbus-x11" ;;
        apk:lxqt)     echo "apk add --no-cache lxqt dbus-x11" ;;
        apk:i3)       echo "apk add --no-cache i3wm dmenu dbus-x11 xterm" ;;
        *) echo "" ;;
    esac
}

storage_guard() {
    local need_mb="$1" have_mb
    have_mb="$(free_mb_home)"
    if [ -n "$have_mb" ] && [ "$have_mb" -gt 0 ] 2>/dev/null && [ "$have_mb" -lt "$need_mb" ] 2>/dev/null; then
        err "only ${have_mb}MB free under \$HOME — a full distro + desktop needs roughly ${need_mb}MB+. Free up space first."
        return 1
    fi
    return 0
}

ram_guard_warn() {
    local style="$1" ram
    ram="$(ram_total_mb)"
    if [ -n "$ram" ] && [ "$ram" -gt 0 ] 2>/dev/null && [ "$ram" -lt 3072 ] 2>/dev/null && [ "$style" = "xfce" ]; then
        warn "this device reports ~${ram}MB RAM — a full distro + xfce will feel heavy here."
        warn "i3 (tiling, far lighter) or the 'light' path instead of 'distro' will run noticeably better."
    fi
}

install_distro() {
    ensure_proot_distro || { err "couldn't install proot-distro"; return 1; }

    local name; name="$(pick_distro)"
    [ -z "$name" ] && { err "no distro chosen — aborting"; return 1; }

    storage_guard 2500 || return 1

    local style; style="$(pick_style)"
    [ -z "$style" ] && { err "no desktop style chosen — aborting"; return 1; }
    ram_guard_warn "$style"

    if distro_installed "$name"; then
        log "'$name' already installed under proot-distro — reusing it."
    else
        local image; image="$(distro_image "$name")"
        log "Pulling $name ($image) via proot-distro — this downloads a real OS image, can take a while..."
        if ! proot-distro install "$image" --name "$name"; then
            err "proot-distro install failed for $image."
            err "If this is an older proot-distro (pre-v5), it may not understand image references —"
            err "run: pkg upgrade proot-distro   then retry."
            return 1
        fi
    fi

    local de_cmd; de_cmd="$(de_install_cmd "$name" "$style")"
    if [ -z "$de_cmd" ]; then
        warn "no known $style package set for $name — you're on your own for the desktop install inside it."
        warn "log in with: proot-distro login $name"
    else
        log "Installing $style desktop inside $name..."
        proot-distro login "$name" -- bash -c "$de_cmd" || \
            warn "desktop package install reported errors — package names can drift between releases; check manually with: proot-distro login $name"
    fi

    echo "distro:$name:$style" > "$STATE_FILE"
    ok "gui-x11 ready ($name + $style, via proot-distro)"
    log "Open the Termux-X11 app first, then re-run this module to launch it."
    log "Manual shell access any time: proot-distro login $name"
}

xstartup_for_distro() {
    case "$1" in
        xfce) echo "dbus-launch --exit-with-session xfce4-session" ;;
        lxqt) echo "dbus-launch --exit-with-session startlxqt" ;;
        i3)   echo "dbus-launch --exit-with-session i3" ;;
    esac
}

run_distro() {
    local name="$1" style="$2"
    if ! distro_installed "$name"; then
        err "'$name' isn't installed under proot-distro anymore — run install again."
        return 1
    fi
    local xstartup; xstartup="$(xstartup_for_distro "$style")"
    log "starting $name + $style over Termux-X11..."
    termux-x11 :0 -xstartup "true" &
    proot-distro login "$name" -- env DISPLAY=:0 bash -c "$xstartup" &
}

# ════════════════════════════════════════════════════════════════
#  Entry point
# ════════════════════════════════════════════════════════════════

# Migrate the old style-only state file transparently, once.
if [ ! -f "$STATE_FILE" ] && [ -f "$LEGACY_STYLE_FILE" ]; then
    echo "light:$(cat "$LEGACY_STYLE_FILE")" > "$STATE_FILE"
fi

case "$1" in
  install)
    install_pkg_quiet x11-repo
    install_pkg_quiet termux-x11-nightly
    path="$(pick_path)"
    [ -z "$path" ] && { err "no path chosen — aborting install"; exit 1; }
    case "$path" in
        light)
            style="$(pick_style)"
            [ -z "$style" ] && { err "no style chosen — aborting install"; exit 1; }
            [ "$style" = "xfce" ] && warn "xfce is the heaviest of the three — lxqt or i3 use noticeably less RAM if that matters on this device."
            log "Installing $style..."
            install_style_light "$style" || exit 1
            echo "light:$style" > "$STATE_FILE"
            ok "gui-x11 ready ($style) — open the Termux-X11 app first, then re-run this"
            ;;
        distro)
            install_distro || exit 1
            ;;
    esac
    log "Switch path/style/distro later without reinstalling everything: bash \$HACKLAB_HOME/modules/gui-x11.sh switch"
    ;;
  switch)
    path="$(pick_path)"
    [ -z "$path" ] && { err "no path chosen"; exit 1; }
    case "$path" in
        light)
            style="$(pick_style)"
            [ -z "$style" ] && { err "no style chosen"; exit 1; }
            install_style_light "$style" || exit 1
            echo "light:$style" > "$STATE_FILE"
            ok "switched to light/$style — run normally to launch it"
            ;;
        distro)
            install_distro || exit 1
            ;;
    esac
    ;;
  run)
    if [ ! -f "$STATE_FILE" ]; then
        err "no path chosen yet — run install first (or: bash \$HACKLAB_HOME/modules/gui-x11.sh switch)"
        exit 1
    fi
    state="$(cat "$STATE_FILE")"
    case "$state" in
        light:*)
            style="${state#light:}"
            xstartup="$(xstartup_for_light "$style")"
            log "starting $style over Termux-X11..."
            termux-x11 :0 -xstartup "$xstartup" &
            ;;
        distro:*)
            rest="${state#distro:}"
            name="${rest%%:*}"
            style="${rest#*:}"
            run_distro "$name" "$style"
            ;;
        *)
            err "unrecognized state file contents — re-run install"
            exit 1
            ;;
    esac
    ;;
  *)
    echo "Usage: $0 {install|switch|run}"
    exit 1
    ;;
esac
