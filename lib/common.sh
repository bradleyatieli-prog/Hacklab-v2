#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  hacklab-v2 / lib/common.sh
#  Shared helpers across the whole project.
# ============================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

log()  { echo -e "${CYAN}[hacklab]${NC} $*"; }
ok()   { echo -e "${GREEN}[ ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
err()  { echo -e "${RED}[fail]${NC} $*" >&2; }

HACKLAB_HOME="${HACKLAB_HOME:-$HOME/.hacklab}"
RUN_DIR="$HACKLAB_HOME/run"
LOG_DIR="$HACKLAB_HOME/logs"
STATE_FILE="$HACKLAB_HOME/installed-modules"
mkdir -p "$HACKLAB_HOME" "$RUN_DIR" "$LOG_DIR"
touch "$STATE_FILE"

# ---- Root detection -------------------------------------------
has_root() {
    command -v su >/dev/null 2>&1 && su -c 'id -u' 2>/dev/null | grep -q '^0$'
}

# ---- Lazy module install tracking ------------------------------
module_installed() { grep -qx "$1" "$STATE_FILE" 2>/dev/null; }
mark_installed()   { echo "$1" >> "$STATE_FILE"; }

# ---- Quiet pkg install ------------------------------------------
install_pkg_quiet() {
    local pkg="$1"
    command -v dpkg >/dev/null 2>&1 && dpkg -s "$pkg" >/dev/null 2>&1 && return 0
    yes | pkg install -y "$pkg" >/dev/null 2>&1
}

# ---- Modern tooling bootstrap (gum, fzf, tmux) -------------------
# gum is officially packaged for Termux (`pkg install gum` is Charm's
# own documented install method for Android) so pkg should normally
# just work. If a repo mirror is stale we fall back to the static
# GitHub release binary — but that release is a statically-linked Go
# binary, and Termux's W^X exec workaround for app-private storage is
# documented to misbehave with static binaries: the binary's own path
# can leak back in as a bogus first CLI argument (manifests as
# `gum: error: unexpected argument /data/.../usr/bin/gum`). So any
# fallback install gets verified by actually *running* it, not just
# trusting `command -v`.
GUM_FALLBACK_VERSION="0.14.5"

verify_cmd() {
    # verify_cmd <cmd> [version-flag] — true only if the command exists
    # AND actually executes cleanly, not just present on PATH.
    local cmd="$1"; shift
    command -v "$cmd" >/dev/null 2>&1 || return 1
    "$cmd" "$@" >/dev/null 2>&1
}

ensure_gum() {
    verify_cmd gum --version && return 0

    install_pkg_quiet gum
    hash -r
    verify_cmd gum --version && return 0

    warn "gum not available from the current repo mirror — refreshing and retrying"
    pkg update -y >/dev/null 2>&1
    install_pkg_quiet gum
    hash -r
    verify_cmd gum --version && return 0

    warn "pkg install still failed — falling back to the static release binary"
    warn "(static Go binaries can hit a known Termux exec quirk — verifying before trusting it)"
    rm -f "$PREFIX/bin/gum"
    local tmp="$HACKLAB_HOME/tmp-gum.tar.gz"
    if curl -fsSL -o "$tmp" \
        "https://github.com/charmbracelet/gum/releases/download/v${GUM_FALLBACK_VERSION}/gum_${GUM_FALLBACK_VERSION}_Linux_arm64.tar.gz" \
        && tar -xzf "$tmp" -C "$PREFIX/bin" --strip-components=1 "gum_${GUM_FALLBACK_VERSION}_Linux_arm64/gum" \
        && chmod +x "$PREFIX/bin/gum"; then
        rm -f "$tmp"
        hash -r
        if verify_cmd gum --version; then
            return 0
        fi
    fi
    rm -f "$tmp" 2>/dev/null

    err "gum could not be installed in a working state — menus will use plain text instead of styled UI"
    rm -f "$PREFIX/bin/gum" 2>/dev/null
    return 1
}

ensure_fzf() {
    verify_cmd fzf --version && return 0
    install_pkg_quiet fzf
    hash -r
    verify_cmd fzf --version && return 0
    warn "fzf not available from the current repo mirror — refreshing and retrying"
    pkg update -y >/dev/null 2>&1
    install_pkg_quiet fzf
    hash -r
    verify_cmd fzf --version
}

ensure_tmux() {
    verify_cmd tmux -V && return 0
    install_pkg_quiet tmux
    hash -r
    verify_cmd tmux -V && return 0
    warn "tmux not available from the current repo mirror — refreshing and retrying"
    pkg update -y >/dev/null 2>&1
    install_pkg_quiet tmux
    hash -r
    verify_cmd tmux -V
}

# ---- Namespace isolation availability (root mode only) ------------
# Stock Android kernels vary wildly in which namespaces are enabled.
# Probe rather than assume.
ns_available() {
    has_root || return 1
    su -c 'unshare --mount --pid --fork true' >/dev/null 2>&1
}
