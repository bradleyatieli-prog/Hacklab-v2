#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  hacklab-v2 / core/menu.sh
#  fzf for fuzzy module search, gum for styled install spinners
#  and confirmations. Each module still installs lazily — this
#  only changes how it's presented.
# ============================================================
source "$HACKLAB_HOME/lib/common.sh"
ensure_fzf || true
ensure_gum || true

MODDIR="$HACKLAB_HOME/modules"

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
        gum confirm "Install '$name' now? (first use only)" || continue
        # Interactive modules (e.g. gui-x11 prompts for a desktop style) can't
        # run under `gum spin` — it hides the prompt and swallows stdin, which
        # makes the install look like it's hanging forever. Run those directly.
        case "$name" in
            gui-x11)
                bash "$script" install
                ;;
            *)
                gum spin --spinner dot --title "Installing $name..." -- bash "$script" install
                ;;
        esac
        mark_installed "$name"
        gum style --foreground 212 "✓ $name installed"
    fi
    bash "$script" run
    gum input --placeholder "press enter to return to menu" >/dev/null
done
