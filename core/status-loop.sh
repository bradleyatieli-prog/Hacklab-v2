#!/data/data/com.termux/files/usr/bin/bash
# Used as the left pane of the tmux dashboard — gum-styled when available,
# refreshes every 2s by clearing and redrawing rather than scrolling.
#
# Deliberately no dialog tier here, even though common.sh now has
# ensure_dialog(): dialog boxes take over the screen with full cursor
# addressing and don't auto-clear on exit, while everything below this
# banner (svc-engine status, mem/load lines) is plain stdout printed at
# whatever line the cursor happens to be on next. Mixing the two every
# 2-second refresh would mean a centered ncurses box sitting above (or
# overlapping) plain-text lines that assume they're printing from the
# top of a freshly cleared screen — a real visual regression, not just
# a less-pretty one. gum style has no such conflict (it prints inline
# and returns), so the fallback here stays gum → plain only.
source "$HACKLAB_HOME/lib/common.sh"
while true; do
    clear
    if verify_cmd gum --version; then
        gum style --border normal --margin "0 1" --padding "0 1" \
            --border-foreground 212 --foreground 212 "hacklab — live status"
    else
        log "hacklab — live status"
    fi
    echo
    bash "$HACKLAB_HOME/lib/svc-engine.sh" status
    echo
    awk '/MemAvailable/{a=$2} /MemTotal/{t=$2} END{
        printf "mem:  %.1fG free / %.1fG total\n", a/1024/1024, t/1024/1024
    }' /proc/meminfo
    awk '{printf "load: %s %s %s\n", $1, $2, $3}' /proc/loadavg
    echo
    if verify_cmd gum --version; then
        gum style --foreground 240 "refreshing every 2s — ctrl-b then arrow keys to move panes"
    else
        echo "refreshing every 2s — ctrl-b then arrow keys to move panes"
    fi
    sleep 2
done
