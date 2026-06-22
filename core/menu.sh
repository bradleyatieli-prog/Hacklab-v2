#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  hacklab-v2 / core/menu.sh
#  fzf for fuzzy module search, gum for styled install spinners
#  and confirmations. Each module still installs lazily — this
#  only changes how it's presented.
#
#  fzf and gum are independent: fzf can work fine even when gum
#  doesn't (e.g. the W^X static-binary exec quirk documented in
#  common.sh). Every gum call below has a plain-text fallback so
#  picking and installing a module never silently breaks just
#  because gum isn't available on this device.
# ============================================================
source "$HACKLAB_HOME/lib/common.sh"
ensure_fzf || true
ensure_gum || true
ensure_dialog || true

MODDIR="$HACKLAB_HOME/modules"

confirm_action() {
    local prompt="$1"
    if verify_cmd gum --version; then
        gum confirm "$prompt"
    elif [ "${DIALOG_OK:-0}" = "1" ]; then
        # --yesno's own exit code is exactly true/false, so just
        # propagate it — 0 only on an explicit "Yes", same as gum
        # confirm and the plain read tier below. Explicit dimensions,
        # not 0 0 — see _term_cols/_term_lines in common.sh for why.
        local w; w=$(( $(_term_cols) - 4 )); [ "$w" -lt 32 ] && w=32; [ "$w" -gt 60 ] && w=60
        dialog --clear --yesno "$prompt" 8 "$w"
        local rc=$?
        tty_clear
        return $rc
    else
        local ans
        read -r -p "$prompt [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]]
    fi
}

run_with_spinner() {
    local title="$1"; shift
    if verify_cmd gum --version; then
        gum spin --spinner dot --title "$title" -- "$@"
    elif [ "${DIALOG_OK:-0}" = "1" ]; then
        # dialog has no animated spinner equivalent — --infobox draws
        # immediately and returns (unlike --msgbox, it doesn't block
        # waiting for a keypress), so it behaves like a "working..."
        # status box rather than a real spinner. Output of "$@" stays
        # hidden the same way gum spin hides it, then we clear so the
        # box doesn't linger once the install/run actually finishes.
        # Explicit dimensions, not 0 0 — see common.sh's _term_cols.
        local w; w=$(( $(_term_cols) - 4 )); [ "$w" -lt 32 ] && w=32; [ "$w" -gt 60 ] && w=60
        dialog --infobox "$title" 5 "$w"
        "$@" >/dev/null 2>&1
        local rc=$?
        tty_clear
        return $rc
    else
        log "$title"
        "$@"
    fi
}

style_ok() {
    # Deliberately two-tier only (gum / plain), no dialog rung here.
    # dialog has no equivalent to a one-line styled message that just
    # prints and scrolls normally — every dialog widget is a modal box
    # drawn at a screen-relative position, so a "✓ installed" box would
    # either need a blocking OK press (wrong UX for a confirmation that
    # should just flash by) or get cleared again immediately (defeating
    # the point of showing it at all). Plain `ok` already does the job
    # fine when gum isn't available.
    if verify_cmd gum --version; then
        gum style --foreground 212 "$1"
    else
        ok "$1"
    fi
}

pause_prompt() {
    if verify_cmd gum --version; then
        gum input --placeholder "press enter to return to menu" >/dev/null
    elif [ "${DIALOG_OK:-0}" = "1" ]; then
        local w; w=$(( $(_term_cols) - 4 )); [ "$w" -lt 32 ] && w=32; [ "$w" -gt 60 ] && w=60
        dialog --msgbox "press enter to return to menu" 8 "$w"
        tty_clear
    else
        read -r -p "press enter to return to menu... "
    fi
}

list_line() {
    local f="$1"
    local name; name="$(basename "$f" .sh)"
    local desc; desc="$(grep -m1 '^# DESC:' "$f" | sed 's/^# DESC: //')"
    local status="not installed"
    module_installed "$name" && status="installed"
    printf "%-16s [%-12s] %s\n" "$name" "$status" "$desc"
}

while true; do
    choice="$(
        for f in "$MODDIR"/*.sh; do list_line "$f"; done | \
        fzf --prompt="hacklab> " --height=70% --border rounded \
            --header "enter: run / lazy-install   ctrl-c: quit" \
            --preview-window=hidden
    )"
    [ -z "$choice" ] && break

    name="$(echo "$choice" | awk '{print $1}')"
    script="$MODDIR/$name.sh"

    if ! module_installed "$name"; then
        confirm_action "Install '$name' now? (first use only)" || continue
        # Interactive modules (e.g. gui-x11 prompts for a desktop style) can't
        # run under `gum spin` — it hides the prompt and swallows stdin, which
        # makes the install look like it's hanging forever. Run those directly.
        case "$name" in
            gui-x11)
                bash "$script" install
                ;;
            *)
                run_with_spinner "Installing $name..." bash "$script" install
                ;;
        esac
        mark_installed "$name"
        style_ok "✓ $name installed"
    fi
    bash "$script" run
    pause_prompt
done
