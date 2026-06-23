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
        # --show-output: gum spin hides the wrapped command's output by
        # default, which combined with install_pkg_quiet's old
        # unconditional /dev/null redirect meant a slow install (lxqt,
        # a full proot-distro desktop) showed literally nothing but a
        # spinner for however many minutes it took. Real apt/pkg
        # progress now flows through underneath the spinner instead.
        gum spin --spinner dot --title "$title" --show-output -- "$@"
    elif [ "${DIALOG_OK:-0}" = "1" ]; then
        # dialog has no animated spinner, and --infobox can't coexist
        # with raw scrolling text the way gum's --show-output can (it'd
        # fight the box for the same screen region) — so instead of a
        # static box with output hidden for the entire run, capture
        # "$@" to a logfile and periodically redraw the infobox with
        # elapsed time + the latest line, so a slow install still
        # visibly shows it's alive rather than just sitting there.
        local w; w=$(( $(_term_cols) - 4 )); [ "$w" -lt 32 ] && w=32; [ "$w" -gt 60 ] && w=60
        local logfile="$LOG_DIR/spinner-$$.log"
        : > "$logfile" 2>/dev/null

        "$@" >"$logfile" 2>&1 &
        local cmd_pid=$!
        local start_ts; start_ts="$(date +%s)"
        while kill -0 "$cmd_pid" 2>/dev/null; do
            local elapsed=$(( $(date +%s) - start_ts ))
            local lastline
            lastline="$(tail -n 1 "$logfile" 2>/dev/null | tr -d '\033\r' | cut -c1-"$w")"
            dialog --infobox "${title}

(${elapsed}s elapsed)
${lastline:-working...}" 8 "$w"
            sleep 1
        done
        wait "$cmd_pid"
        local rc=$?
        rm -f "$logfile" 2>/dev/null
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
        install_rc=0
        case "$name" in
            gui-x11)
                bash "$script" install || install_rc=$?
                ;;
            *)
                run_with_spinner "Installing $name..." bash "$script" install || install_rc=$?
                ;;
        esac
        # This used to be unconditional — mark_installed + "✓ installed"
        # ran no matter what the install command actually returned, so a
        # genuine failure (dpkg dependency errors, a 404, no space left)
        # still got reported as a success and silently marked installed,
        # hiding the failure on every future visit to this menu too.
        if [ "$install_rc" -ne 0 ]; then
            err "$name install failed (exit $install_rc) — not marked installed. Check \$HACKLAB_HOME/logs/ for details."
            pause_prompt
            continue
        fi
        mark_installed "$name"
        style_ok "✓ $name installed"
    fi
    bash "$script" run
    pause_prompt
done
