#!/data/data/com.termux/files/usr/bin/bash
# Used as the left pane of the tmux dashboard — gum-styled when available,
# refreshes every 2s by clearing and redrawing rather than scrolling.
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
