#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  hacklab-v2 / lib/svc-engine.sh
#
#  A real service supervisor — not a flat list of background jobs.
#  Each service is a directory:
#
#    services/<name>/run        executable, the actual process
#    services/<name>/type       "longrun" or "oneshot"
#    services/<name>/depends    newline list of services that
#                                 must be up first (optional)
#    services/<name>/isolate    "none" | "mountns" | "netns" | "full"
#                                 (optional, default "none")
#    services/<name>/healthcheck  executable, exit 0 = healthy
#                                 (optional)
#
#  Dependency order is resolved with a DFS topological sort and
#  cycle detection — this is the difference between this and just
#  backgrounding processes in install-script order.
#
#  Usage: svc-engine.sh up|down|status|restart <name>|logs <name>
# ============================================================
source "$HACKLAB_HOME/lib/common.sh"

SERVICES_DIR="$HACKLAB_HOME/services"

# ---- topological sort -------------------------------------------
declare -A VISITED VISITING
ORDER=()

_visit() {
    local name="$1"
    [ -n "${VISITED[$name]}" ] && return
    if [ -n "${VISITING[$name]}" ]; then
        err "dependency cycle detected at '$name' — refusing to start"
        exit 1
    fi
    VISITING[$name]=1
    local depfile="$SERVICES_DIR/$name/depends"
    if [ -f "$depfile" ]; then
        while IFS= read -r dep; do
            [ -z "$dep" ] && continue
            [ -d "$SERVICES_DIR/$dep" ] || { err "service '$name' depends on missing service '$dep'"; exit 1; }
            _visit "$dep"
        done < "$depfile"
    fi
    unset 'VISITING[$name]'
    VISITED[$name]=1
    ORDER+=("$name")
}

resolve_order() {
    ORDER=(); VISITED=(); VISITING=()
    for d in "$SERVICES_DIR"/*/; do
        [ -d "$d" ] || continue
        _visit "$(basename "$d")"
    done
}

# ---- isolation wrapper --------------------------------------------
# Builds the actual command line a service runs under, given its
# isolate mode. Falls back to plain execution if root/namespaces
# aren't available — logged once, not failed silently.
_wrap_isolation() {
    local name="$1" cmd="$2"
    local mode="none"
    [ -f "$SERVICES_DIR/$name/isolate" ] && mode="$(cat "$SERVICES_DIR/$name/isolate")"

    if [ "$mode" = "none" ]; then
        echo "$cmd"
        return
    fi
    if ! ns_available; then
        warn "$name requested isolation '$mode' but namespaces unavailable (no root or kernel doesn't support it) — running unisolated"
        echo "$cmd"
        return
    fi
    case "$mode" in
        mountns) echo "su -c 'unshare --mount -- $cmd'" ;;
        netns)   echo "su -c 'unshare --net -- $cmd'" ;;
        full)    echo "su -c 'unshare --mount --net --pid --fork -- $cmd'" ;;
        *) echo "$cmd" ;;
    esac
}

# ---- start / stop one service --------------------------------------
_start_one() {
    local name="$1"
    local dir="$SERVICES_DIR/$name"
    local type="longrun"
    [ -f "$dir/type" ] && type="$(cat "$dir/type")"

    if [ "$type" = "oneshot" ]; then
        if [ -f "$RUN_DIR/$name.done" ]; then
            return
        fi
        log "running oneshot: $name"
        bash "$dir/run" >> "$LOG_DIR/$name.log" 2>&1
        touch "$RUN_DIR/$name.done"
        return
    fi

    # longrun
    if [ -f "$RUN_DIR/$name.pid" ] && kill -0 "$(cat "$RUN_DIR/$name.pid")" 2>/dev/null; then
        return  # already up
    fi
    local cmd
    cmd="$(_wrap_isolation "$name" "bash $dir/run")"
    log "starting: $name"
    setsid bash -c "$cmd" >> "$LOG_DIR/$name.log" 2>&1 &
    echo $! > "$RUN_DIR/$name.pid"
    echo "up" > "$RUN_DIR/$name.status"
}

_stop_one() {
    local name="$1"
    [ -f "$RUN_DIR/$name.pid" ] || return
    local pid; pid="$(cat "$RUN_DIR/$name.pid")"
    if kill -0 "$pid" 2>/dev/null; then
        # negative PID = whole process group (setsid made this its own group)
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    fi
    rm -f "$RUN_DIR/$name.pid"
    echo "down" > "$RUN_DIR/$name.status"
}

_health_of() {
    local name="$1"
    local dir="$SERVICES_DIR/$name"
    [ -f "$dir/healthcheck" ] || { echo "n/a"; return; }
    bash "$dir/healthcheck" >/dev/null 2>&1 && echo "healthy" || echo "unhealthy"
}

# ---- single-service start (with its own dependency chain only) -------
# Used by the unified launcher and the web control panel, where someone
# wants to bring up just `webdash` without restarting everything `up`
# would touch. Walks only this service's `depends` chain, not the full
# directory-order topological sort.
declare -a _DEP_ORDER
_collect_deps() {
    local name="$1"
    local depfile="$SERVICES_DIR/$name/depends"
    if [ -f "$depfile" ]; then
        while IFS= read -r dep; do
            [ -z "$dep" ] && continue
            [ -d "$SERVICES_DIR/$dep" ] || { err "service '$name' depends on missing service '$dep'"; exit 1; }
            _collect_deps "$dep"
        done < "$depfile"
    fi
    _DEP_ORDER+=("$name")
}

cmd_start_one() {
    local target="$1"
    [ -d "$SERVICES_DIR/$target" ] || { err "unknown service '$target'"; exit 1; }
    _DEP_ORDER=()
    _collect_deps "$target"
    declare -A seen
    for name in "${_DEP_ORDER[@]}"; do
        [ -n "${seen[$name]}" ] && continue
        seen[$name]=1
        [ -f "$SERVICES_DIR/$name/disabled" ] && continue
        _start_one "$name"
    done
}

cmd_stop_one() {
    local target="$1"
    [ -d "$SERVICES_DIR/$target" ] || { err "unknown service '$target'"; exit 1; }
    _stop_one "$target"
}

# ---- public commands -------------------------------------------------
cmd_up() {
    resolve_order
    for name in "${ORDER[@]}"; do
        [ -f "$SERVICES_DIR/$name/disabled" ] && continue
        _start_one "$name"
    done
}

cmd_down() {
    resolve_order
    local rev=()
    for ((i=${#ORDER[@]}-1; i>=0; i--)); do rev+=("${ORDER[$i]}"); done
    for name in "${rev[@]}"; do
        local type="longrun"
        [ -f "$SERVICES_DIR/$name/type" ] && type="$(cat "$SERVICES_DIR/$name/type")"
        [ "$type" = "longrun" ] && _stop_one "$name"
    done
}

cmd_status() {
    resolve_order
    printf "%-14s %-9s %-8s %-10s\n" "SERVICE" "TYPE" "PID" "HEALTH"
    for name in "${ORDER[@]}"; do
        local type="longrun"
        [ -f "$SERVICES_DIR/$name/type" ] && type="$(cat "$SERVICES_DIR/$name/type")"
        local pid="-"
        if [ "$type" = "longrun" ] && [ -f "$RUN_DIR/$name.pid" ]; then
            local p; p="$(cat "$RUN_DIR/$name.pid")"
            kill -0 "$p" 2>/dev/null && pid="$p" || pid="dead"
        elif [ "$type" = "oneshot" ]; then
            [ -f "$RUN_DIR/$name.done" ] && pid="done" || pid="pending"
        fi
        printf "%-14s %-9s %-8s %-10s\n" "$name" "$type" "$pid" "$(_health_of "$name")"
    done
}

case "$1" in
    up) cmd_up ;;
    down) cmd_down ;;
    status) cmd_status ;;
    start) [ -n "$2" ] && cmd_start_one "$2" ;;
    stop) [ -n "$2" ] && cmd_stop_one "$2" ;;
    restart) [ -n "$2" ] && { _stop_one "$2"; sleep 1; _start_one "$2"; } ;;
    logs) [ -n "$2" ] && tail -n 50 -f "$LOG_DIR/$2.log" ;;
    *) echo "Usage: $0 {up|down|status|start <name>|stop <name>|restart <name>|logs <name>}"; exit 1 ;;
esac
