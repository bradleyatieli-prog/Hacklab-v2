#!/data/data/com.termux/files/usr/bin/bash
# Live TUI dashboard. Three tmux panes: status / log tail / shell.
# Re-attaches instead of duplicating if a session is already running.
source "$HACKLAB_HOME/lib/common.sh"
ensure_tmux || true; ensure_gum || true

SESSION=hacklab
if tmux has-session -t "$SESSION" 2>/dev/null; then
    exec tmux attach -t "$SESSION"
fi

tmux new-session -d -s "$SESSION" -n dash "bash '$HACKLAB_HOME/core/status-loop.sh'"
tmux split-window -h -t "${SESSION}:dash.0" "tail -n 30 -f '$LOG_DIR'/*.log 2>/dev/null || sleep infinity"
tmux split-window -v -t "${SESSION}:dash.1" -p 40 -c "$HOME"
tmux select-pane -t "${SESSION}:dash.0"
exec tmux attach -t "$SESSION"
