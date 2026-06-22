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
GUM_MARKER="$HACKLAB_HOME/.gum-unavailable"

verify_cmd() {
    # verify_cmd <cmd> [version-flag] — true only if the command exists
    # AND actually executes cleanly, not just present on PATH.
    local cmd="$1"; shift
    command -v "$cmd" >/dev/null 2>&1 || return 1
    "$cmd" "$@" >/dev/null 2>&1
}

# tty_clear — clear the real screen without going through stdout.
# Several dialog-tier helpers (confirm_action, run_with_spinner,
# pause_prompt, dialog_menu) need to clear leftover box artifacts
# after dialog exits. A bare `clear` writes its escape sequence to
# stdout — harmless when nothing's capturing it, but several callers
# DO capture stdout (e.g. `pick="$(choose ...)"` in bin/hacklab), and
# a plain `clear` would silently leak terminal control codes into that
# captured value. Writing straight to /dev/tty sidesteps that
# entirely; the `|| true` covers the rare case of no controlling tty
# (e.g. running under a test harness) where it would otherwise abort
# a caller under `set -e`.
tty_clear() { { clear >/dev/tty; } 2>/dev/null || true; }

ensure_gum() {
    verify_cmd gum --version && { rm -f "$GUM_MARKER" 2>/dev/null; return 0; }

    # If we already proved today that gum doesn't work on this device,
    # don't repeat the ~20s pkg/curl retry sequence on every launch — just
    # fail fast and silently. Still re-checked once per day in case a repo
    # mirror or device quirk gets fixed in the meantime.
    if [ -f "$GUM_MARKER" ] && [ "$(cat "$GUM_MARKER" 2>/dev/null)" = "$(date +%Y-%m-%d)" ]; then
        return 1
    fi

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
    hash -r
    date +%Y-%m-%d > "$GUM_MARKER" 2>/dev/null
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

# ---- dialog: second tier between gum and plain read/select ---------
# gum is a statically-linked Go binary, which is the actual reason it
# can fail outright on some devices (the W^X exec quirk documented
# above on ensure_gum). dialog/whiptail are old C programs built
# directly against ncurses — no static-binary exec path to misfire,
# and they've shipped in Termux's main repo for over a decade — so
# they're a meaningfully more reliable "still styled" fallback than
# dropping straight to plain read/select the moment gum is missing.
# Same caching behavior as ensure_gum: don't repeat a failed pkg
# install on every single launch, just fail fast for the rest of the
# day and let plain text take over.
DIALOG_MARKER="$HACKLAB_HOME/.dialog-unavailable"

# ---- terminal geometry, shared by every dialog widget below -------
# dialog's own "0 0" ("auto-size to terminal") depends on dialog
# correctly detecting the real terminal geometry itself — and that's
# exactly the same category of bug BOX_W had in install.sh before it
# was fixed: when that detection comes back wrong/degenerate, dialog
# can end up drawing an invisible, zero-sized box that's technically
# running and waiting for input, but shows nothing at all on screen.
# Same fix here: detect real cols/lines ourselves (tput → stty → env
# → fallback) and always hand dialog real, clamped numbers — never 0 0.
_term_cols() {
    local c
    c="$(tput cols 2>/dev/null)"
    [ -z "$c" ] && c="$(stty size 2>/dev/null | awk '{print $2}')"
    [ -z "$c" ] && [ -n "${COLUMNS:-}" ] && c="$COLUMNS"
    [ -z "$c" ] && c=64
    [ "$c" -lt 36 ] && c=36
    echo "$c"
}
_term_lines() {
    local l
    l="$(tput lines 2>/dev/null)"
    [ -z "$l" ] && l="$(stty size 2>/dev/null | awk '{print $1}')"
    [ -z "$l" ] && [ -n "${LINES:-}" ] && l="$LINES"
    [ -z "$l" ] && l=24
    [ "$l" -lt 12 ] && l=12
    echo "$l"
}

ensure_dialog() {
    verify_cmd dialog --version && { rm -f "$DIALOG_MARKER" 2>/dev/null; return 0; }

    if [ -f "$DIALOG_MARKER" ] && [ "$(cat "$DIALOG_MARKER" 2>/dev/null)" = "$(date +%Y-%m-%d)" ]; then
        return 1
    fi

    install_pkg_quiet dialog
    hash -r
    verify_cmd dialog --version && return 0

    warn "dialog not available from the current repo mirror — refreshing and retrying"
    pkg update -y >/dev/null 2>&1
    install_pkg_quiet dialog
    hash -r
    verify_cmd dialog --version && return 0

    warn "dialog could not be installed either — this tier will be skipped, plain text only"
    date +%Y-%m-%d > "$DIALOG_MARKER" 2>/dev/null
    return 1
}

# dialog_menu <header> <option> [option ...]
# Shared picker used anywhere a gum-choose-style menu needs a dialog
# fallback (bin/hacklab's choose(), and anywhere else that wants one).
# Echoes the chosen option text verbatim — same contract as gum choose
# and plain `select` — so callers can keep matching on it unchanged.
# Empty echo on cancel (Esc/back), never a hard failure.
#
# dialog writes the selected *tag* to stderr by default, not stdout —
# the `exec 3>&1 ... 2>&1 1>&3` swap below is the standard idiom for
# capturing that result while leaving the box's own screen drawing
# (which bypasses stdout/stderr entirely via the terminal device)
# untouched. Height/width are computed explicitly via _term_cols/
# _term_lines, not dialog's own "0 0" auto-size — see the comment
# above those two functions for why.
dialog_menu() {
    local header="$1"; shift
    local n=$#
    [ "$n" -eq 0 ] && { echo ""; return; }

    local args=() i=0
    for opt in "$@"; do
        i=$((i+1))
        args+=("$i" "$opt")
    done
    local rows=$n
    [ "$rows" -gt 12 ] && rows=12

    local cols lines w h maxh
    cols="$(_term_cols)"; lines="$(_term_lines)"
    w=$(( cols - 4 )); [ "$w" -lt 32 ] && w=32; [ "$w" -gt 70 ] && w=70
    maxh=$(( lines - 4 )); [ "$maxh" -lt 8 ] && maxh=8
    h=$(( rows + 6 )); [ "$h" -gt "$maxh" ] && h="$maxh"; [ "$h" -lt 8 ] && h=8

    local tag rc
    exec 3>&1
    tag="$(dialog --clear --menu "$header" "$h" "$w" "$rows" "${args[@]}" 2>&1 1>&3)"
    rc=$?
    exec 3>&-
    tty_clear

    if [ "$rc" -ne 0 ] || [ -z "$tag" ]; then
        echo ""
        return
    fi
    echo "${@:$tag:1}"
}

# ---- Namespace isolation availability (root mode only) ------------
# Stock Android kernels vary wildly in which namespaces are enabled.
# Probe rather than assume.
ns_available() {
    has_root || return 1
    su -c 'unshare --mount --pid --fork true' >/dev/null 2>&1
}
