#!/data/data/com.termux/files/usr/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
#  hacklab-v2 / install.sh
#  Phases:
#    0 · banner
#    1 · hardware detection & accelerator profile
#    2 · core install
#    3 · modern tooling  (+ GPU compute packages if detected)
#    4 · root detection
#    5 · boot-time path
#    6 · animated summary
#    7 · next-steps card
# ╚══════════════════════════════════════════════════════════════════╝
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
export HACKLAB_HOME="$HOME/.hacklab"
INSTALL_START="$(date +%s)"

UPGRADE=0
[ -f "$HACKLAB_HOME/lib/common.sh" ] && UPGRADE=1

mkdir -p "$HACKLAB_HOME/lib"
if ! cp -r "$HERE/lib/." "$HACKLAB_HOME/lib/"; then
    echo "fatal: couldn't stage lib/ — aborting" >&2; exit 1
fi
source "$HACKLAB_HOME/lib/common.sh"

# ════════════════════════════════════════════════════════════════
#  ANSI palette
# ════════════════════════════════════════════════════════════════
BOLD='\033[1m'; DIM='\033[2m'
C_CYAN='\033[0;36m';   C_BCYAN='\033[1;36m'
C_GREEN='\033[0;32m';  C_BGREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m';    C_BRED='\033[1;31m'
C_WHITE='\033[1;37m'
C_PURPLE='\033[0;35m'; C_BPURPLE='\033[1;35m'
C_ORANGE='\033[0;33m'; C_BORNG='\033[1;33m'
NC='\033[0m'

# ════════════════════════════════════════════════════════════════
#  Step tracking
# ════════════════════════════════════════════════════════════════
declare -A STEP_STATUS STEP_DETAIL
STEP_ORDER=()
HAVE_GUM=0
STEP_TOTAL=22   # banner+hw(2)+core(8)+tools(5)+hw-tools(2)+root(1)+boot(1)+summary(3)
PROG_DONE=0

record() {
    STEP_STATUS["$1"]="$2"; STEP_DETAIL["$1"]="${3:-}"
    local found=0
    for s in "${STEP_ORDER[@]:-}"; do [ "$s" = "$1" ] && found=1; done
    [ "$found" = 0 ] && STEP_ORDER+=("$1")
}

# ════════════════════════════════════════════════════════════════
#  Box drawing
# ════════════════════════════════════════════════════════════════
BOX_W=62

box_top() {
    local title="$1" color="${2:-$C_CYAN}"
    local inner=$((BOX_W-2)) tlen=${#title}
    local left right
    left=$(( (inner-tlen-2)/2 ))
    right=$(( inner-tlen-2-left ))
    printf "${color}┌"; printf '─%.0s' $(seq 1 $left)
    printf "┤ ${C_WHITE}${BOLD}%s${NC}${color} ├" "$title"
    printf '─%.0s' $(seq 1 $right); printf "┐${NC}\n"
}
box_line() {
    local text="${1:-}" color="${2:-$C_CYAN}" inner=$((BOX_W-2))
    local vis; vis=$(printf '%b' "$text" | sed 's/\x1b\[[0-9;]*[mK]//g')
    local pad=$(( inner - ${#vis} - 2 )); [ $pad -lt 0 ] && pad=0
    printf "${color}│${NC} "; printf '%b' "$text"
    printf '%*s' $pad ''; printf " ${color}│${NC}\n"
}
box_blank() {
    local color="${1:-$C_CYAN}" inner=$((BOX_W-2))
    printf "${color}│${NC}%*s${color}│${NC}\n" $inner ''
}
box_bottom() {
    local color="${1:-$C_CYAN}" inner=$((BOX_W-2))
    printf "${color}└"; printf '─%.0s' $(seq 1 $inner); printf "┘${NC}\n"
}
box_divider() {
    local color="${1:-$C_CYAN}" inner=$((BOX_W-2))
    printf "${color}├"; printf '─%.0s' $(seq 1 $inner); printf "┤${NC}\n"
}

# ════════════════════════════════════════════════════════════════
#  Section header
# ════════════════════════════════════════════════════════════════
PHASE=0
section() {
    PHASE=$((PHASE+1))
    echo
    local label="  ▸  PHASE ${PHASE}  ·  $(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')  ◂  "
    local llen=${#label}
    local pad=$(( (BOX_W - llen) / 2 )); [ $pad -lt 1 ] && pad=1
    local rpad=$(( BOX_W - pad - llen )); [ $rpad -lt 1 ] && rpad=1
    printf "${C_BCYAN}"; printf '═%.0s' $(seq 1 $BOX_W); echo
    printf '═%.0s' $(seq 1 $pad)
    printf "${C_WHITE}${BOLD}%s${NC}${C_BCYAN}" "$label"
    printf '═%.0s' $(seq 1 $rpad); echo
    printf '═%.0s' $(seq 1 $BOX_W); printf "${NC}\n"
}

# ════════════════════════════════════════════════════════════════
#  Progress bar
# ════════════════════════════════════════════════════════════════
draw_progress() {
    PROG_DONE=$((PROG_DONE+1))
    local pct=$(( PROG_DONE * 100 / STEP_TOTAL ))
    local filled=$(( PROG_DONE * 44 / STEP_TOTAL ))
    local empty=$(( 44 - filled ))
    [ $pct -gt 100 ] && pct=100; [ $filled -gt 44 ] && filled=44; [ $empty -lt 0 ] && empty=0
    printf "  ${DIM}▕${NC}"
    printf "${C_BGREEN}%${filled}s" '' | tr ' ' '█'
    printf "${DIM}%${empty}s" '' | tr ' ' '▒'
    printf "${DIM}▏${NC} ${C_WHITE}${BOLD}%3d%%${NC}  ${DIM}step %d/%d${NC}\n" \
        "$pct" "$PROG_DONE" "$STEP_TOTAL"
}

# ════════════════════════════════════════════════════════════════
#  Spinner
# ════════════════════════════════════════════════════════════════
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
_spin_pid=""
spin_start() {
    ( local i=0
      while true; do
          printf '\r  %b%s%b  %b%s%b  ' \
              "$C_CYAN" "${SPINNER_FRAMES[$((i%10))]}" "$NC" \
              "$C_WHITE" "$1" "$NC"
          i=$((i+1)); sleep 0.09
      done ) &
    _spin_pid=$!
}
spin_stop() {
    [ -n "$_spin_pid" ] && { kill "$_spin_pid" 2>/dev/null
        wait "$_spin_pid" 2>/dev/null; _spin_pid=""; printf '\r\033[K'; }
}

# ════════════════════════════════════════════════════════════════
#  step / tick / bootstrap_tool
# ════════════════════════════════════════════════════════════════
step() {
    local key="$1" label="$2"; shift 2
    [ "${1:-}" = "--" ] && shift
    local logfile; logfile="$(mktemp)"; local rc=0
    if [ "$HAVE_GUM" = 1 ]; then
        gum spin --spinner dot --title "  $label" -- "$@" >"$logfile" 2>&1 || rc=$?
    else
        [ -t 1 ] && spin_start "$label"
        "$@" >"$logfile" 2>&1 || rc=$?
        [ -t 1 ] && spin_stop
    fi
    if [ "$rc" -eq 0 ]; then
        record "$key" ok ""
        printf "  ${C_BGREEN}✓${NC}  ${C_WHITE}%-30s${NC} ${C_BGREEN}done${NC}\n" "$label"
    else
        record "$key" fail "$(tail -n1 "$logfile" 2>/dev/null | cut -c1-38)"
        printf "  ${C_BRED}✗${NC}  ${C_WHITE}%-30s${NC} ${C_RED}FAILED${NC}\n" "$label"
    fi
    draw_progress; rm -f "$logfile"; return "$rc"
}

tick() {
    local key="$1" label="$2"; shift 2; local rc=0
    if "$@" >/dev/null 2>&1; then
        record "$key" ok ""
        printf "  ${C_BGREEN}✓${NC}  ${C_WHITE}%-30s${NC} ${C_BGREEN}done${NC}\n" "$label"
    else
        rc=1; record "$key" fail "command failed"
        printf "  ${C_BRED}✗${NC}  ${C_WHITE}%-30s${NC} ${C_RED}FAILED${NC}\n" "$label"
    fi
    draw_progress; return $rc
}

bootstrap_tool() {
    local key="$1" label="$2" ensure_fn="$3"; shift 3; local rc=0
    [ -t 1 ] && spin_start "$label"
    "$ensure_fn" >/dev/null 2>&1 || rc=$?
    [ -t 1 ] && spin_stop
    if [ "$rc" -eq 0 ]; then
        local ver; ver="$("$@" 2>/dev/null | head -n1)"
        record "$key" ok "$ver"
        printf "  ${C_BGREEN}✓${NC}  ${C_WHITE}%-12s${NC}  ${C_CYAN}%s${NC}\n" "$label" "$ver"
    else
        record "$key" fail "unavailable — degraded mode"
        printf "  ${C_YELLOW}⚠${NC}   ${C_WHITE}%-12s${NC}  ${C_YELLOW}unavailable — degraded mode${NC}\n" "$label"
    fi
    draw_progress; return "$rc"
}

# ════════════════════════════════════════════════════════════════
#  Critical-step guard
# ════════════════════════════════════════════════════════════════
CRITICAL_STEPS=(core-services core-tui core-modules core-webdash
                core-bin core-perms core-svc-perms launcher)
critical_failed() {
    local k; for k in "${CRITICAL_STEPS[@]}"; do
        [ "${STEP_STATUS[$k]:-fail}" = "fail" ] && return 0; done; return 1
}
bail_if_critical_failed() {
    critical_failed || return 0
    echo
    printf "${C_BRED}╔══ FATAL ════════════════════════════════════════════════════╗${NC}\n"
    printf "${C_BRED}║${NC}  Critical install step failed — fix ✗ items and re-run.    ${C_BRED}║${NC}\n"
    printf "${C_BRED}╚═════════════════════════════════════════════════════════════╝${NC}\n"
    exit 1
}

# ════════════════════════════════════════════════════════════════
#  ██████╗   HARDWARE  DETECTION  ENGINE
# ════════════════════════════════════════════════════════════════

# ── CPU ──────────────────────────────────────────────────────
detect_cpu() {
    HW_CPU_ARCH="$(uname -m)"
    HW_CPU_CORES="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 4)"

    # big.LITTLE cluster analysis via cpufreq policy groups
    local big_cores=0 little_cores=0 overall_max=0
    if [ -d /sys/devices/system/cpu/cpufreq ]; then
        for policy in /sys/devices/system/cpu/cpufreq/policy*/; do
            local f; f=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo 0)
            [ "$f" -gt "$overall_max" ] 2>/dev/null && overall_max=$f
        done
        for policy in /sys/devices/system/cpu/cpufreq/policy*/; do
            local f; f=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null || echo 0)
            local count; count=$(wc -w < "$policy/related_cpus" 2>/dev/null || echo 0)
            if [ "$f" = "$overall_max" ] && [ "$overall_max" -gt 0 ]; then
                big_cores=$((big_cores + count))
            else
                little_cores=$((little_cores + count))
            fi
        done
    fi
    HW_CPU_BIG_CORES=$big_cores
    HW_CPU_LITTLE_CORES=$little_cores

    # ISA feature flags from /proc/cpuinfo
    local feats; feats=$(grep -m1 '^Features' /proc/cpuinfo 2>/dev/null | cut -d: -f2 || echo '')
    HW_CPU_HAS_NEON=0;   echo "$feats" | grep -qwE 'asimd|neon'  && HW_CPU_HAS_NEON=1
    HW_CPU_HAS_SVE=0;    echo "$feats" | grep -qw  'sve'          && HW_CPU_HAS_SVE=1
    HW_CPU_HAS_SVE2=0;   echo "$feats" | grep -qw  'sve2'         && HW_CPU_HAS_SVE2=1
    HW_CPU_HAS_AES=0;    echo "$feats" | grep -qw  'aes'          && HW_CPU_HAS_AES=1
    HW_CPU_HAS_SHA=0;    echo "$feats" | grep -qwE 'sha1|sha2'    && HW_CPU_HAS_SHA=1
    HW_CPU_HAS_CRC32=0;  echo "$feats" | grep -qw  'crc32'        && HW_CPU_HAS_CRC32=1
    HW_CPU_HAS_FP16=0;   echo "$feats" | grep -qwE 'fphp|asimdhp' && HW_CPU_HAS_FP16=1
    HW_CPU_HAS_DOTPROD=0; echo "$feats" | grep -qw 'asimddp'      && HW_CPU_HAS_DOTPROD=1
    HW_CPU_HAS_I8MM=0;   echo "$feats" | grep -qw  'i8mm'         && HW_CPU_HAS_I8MM=1

    # CPU hardware model
    HW_CPU_MODEL=$(grep -m1 '^Hardware' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || \
                   grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || \
                   echo "ARM $(uname -m)")

    # Max clock across all cores
    local mhz=0
    for f in /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq; do
        [ -f "$f" ] || continue
        local v; v=$(cat "$f" 2>/dev/null); [ "${v:-0}" -gt "$mhz" ] 2>/dev/null && mhz=$v
    done
    HW_CPU_MAX_MHZ=$((mhz / 1000))

    # Derive optimal nmap parallelism: big cores × 4, capped 8–128
    local accel=$HW_CPU_BIG_CORES
    [ "$accel" -eq 0 ] && accel=$HW_CPU_CORES
    HW_NMAP_PARALLEL=$((accel * 4))
    [ $HW_NMAP_PARALLEL -gt 128 ] && HW_NMAP_PARALLEL=128
    [ $HW_NMAP_PARALLEL -lt 8  ] && HW_NMAP_PARALLEL=8

    # Thread count for multi-threaded tools (john, hashcat CPU, etc.)
    HW_OMP_THREADS=$HW_CPU_CORES
    [ "$HW_CPU_BIG_CORES" -gt 0 ] && HW_OMP_THREADS=$HW_CPU_BIG_CORES
}

# ── GPU ──────────────────────────────────────────────────────
detect_gpu() {
    HW_GPU_VENDOR="none"; HW_GPU_MODEL="none"; HW_GPU_NODE=""
    HW_GPU_OPENCL=0; HW_GPU_VULKAN=0
    HW_GPU_MAX_FREQ_MHZ=0; HW_GPU_SCORE=0
    HW_HASHCAT_DEVICE_TYPE=1   # 1=CPU default; 2=GPU if OpenCL found

    # ─── Qualcomm Adreno (kgsl subsystem) ──────────────────
    if [ -d /sys/class/kgsl/kgsl-3d0 ] || [ -e /dev/kgsl-3d0 ]; then
        HW_GPU_VENDOR="qualcomm"; HW_GPU_NODE="/dev/kgsl-3d0"

        # Direct sysfs model string (newer kernels expose this)
        local gm=""
        for p in /sys/class/kgsl/kgsl-3d0/gpu_model \
                  /sys/bus/platform/drivers/kgsl/*/gpu_model; do
            [ -f "$p" ] && { gm=$(cat "$p" 2>/dev/null | tr -d '\n'); break; }
        done

        # Fallback: map SoC platform string → Adreno model
        if [ -z "$gm" ]; then
            local plat; plat=$(getprop ro.board.platform 2>/dev/null || \
                               getprop ro.hardware 2>/dev/null || echo "")
            case "${plat,,}" in
                sm8650*|kalama*)   gm="Adreno 750" ; HW_GPU_SCORE=95 ;;
                sm8550*|crow*)     gm="Adreno 740" ; HW_GPU_SCORE=92 ;;
                sm8475*|cape*)     gm="Adreno 730" ; HW_GPU_SCORE=88 ;;
                sm8450*|taro*)     gm="Adreno 730" ; HW_GPU_SCORE=88 ;;
                sm8350*|lahaina*)  gm="Adreno 660" ; HW_GPU_SCORE=78 ;;
                sm8250*|kona*)     gm="Adreno 650" ; HW_GPU_SCORE=72 ;;
                sm8150*|msmnile*)  gm="Adreno 640" ; HW_GPU_SCORE=65 ;;
                sm7550*)           gm="Adreno 735" ; HW_GPU_SCORE=75 ;;
                sm7450*|yupik*)    gm="Adreno 725" ; HW_GPU_SCORE=68 ;;
                sm7325*|lahainap*) gm="Adreno 642L"; HW_GPU_SCORE=60 ;;
                sm6375*)           gm="Adreno 619" ; HW_GPU_SCORE=48 ;;
                sm6150*)           gm="Adreno 612" ; HW_GPU_SCORE=38 ;;
                *)                 gm="Adreno (SoC: ${plat:-?})" ; HW_GPU_SCORE=50 ;;
            esac
        else
            HW_GPU_SCORE=80   # sysfs gave us a real string — reasonable floor
        fi
        HW_GPU_MODEL="$gm"

        # Max GPU clock
        for p in /sys/class/kgsl/kgsl-3d0/devfreq/max_freq \
                  /sys/class/kgsl/kgsl-3d0/max_gpuclk \
                  /sys/bus/platform/drivers/kgsl/*/devfreq/max_freq; do
            [ -f "$p" ] || continue
            local hz; hz=$(cat "$p" 2>/dev/null || echo 0)
            [ "${hz:-0}" -gt 0 ] 2>/dev/null && { HW_GPU_MAX_FREQ_MHZ=$((hz/1000000)); break; }
        done

        # Try to set kgsl governor to performance (needs write access — no-root mostly fails)
        for p in /sys/class/kgsl/kgsl-3d0/devfreq/governor \
                  /sys/bus/platform/drivers/kgsl/*/devfreq/governor; do
            [ -w "$p" ] && echo "performance" > "$p" 2>/dev/null && break
        done
        # Lock GPU to max freq if possible
        for p in /sys/class/kgsl/kgsl-3d0/min_pwrlevel; do
            [ -w "$p" ] && echo "0" > "$p" 2>/dev/null
        done
    fi

    # ─── ARM Mali ──────────────────────────────────────────
    if ls /dev/mali* 2>/dev/null | grep -q .; then
        HW_GPU_VENDOR="arm"
        HW_GPU_NODE=$(ls /dev/mali* 2>/dev/null | head -1)
        local plat; plat=$(getprop ro.board.platform 2>/dev/null || echo "")
        case "${plat,,}" in
            mt6983*|dimensity9200*) HW_GPU_MODEL="Immortalis-G715 MC11"; HW_GPU_SCORE=90 ;;
            mt6895*|dimensity9000*) HW_GPU_MODEL="Mali-G710 MC10";        HW_GPU_SCORE=82 ;;
            mt6893*|dimensity1200*) HW_GPU_MODEL="Mali-G77 MC9";          HW_GPU_SCORE=65 ;;
            mt6891*|dimensity1100*) HW_GPU_MODEL="Mali-G77 MP9";          HW_GPU_SCORE=62 ;;
            mt6785*|dimensity820*)  HW_GPU_MODEL="Mali-G57 MC5";          HW_GPU_SCORE=42 ;;
            mt6768*|helio*)         HW_GPU_MODEL="Mali-G52 MC2";          HW_GPU_SCORE=28 ;;
            exynos2400*)            HW_GPU_MODEL="Xclipse 940 (RDNA3)";   HW_GPU_SCORE=95
                                    HW_GPU_VENDOR="amd" ;;
            exynos2200*)            HW_GPU_MODEL="Xclipse 920 (RDNA2)";   HW_GPU_SCORE=90
                                    HW_GPU_VENDOR="amd" ;;
            exynos2100*)            HW_GPU_MODEL="Mali-G78 MP14";         HW_GPU_SCORE=78 ;;
            exynos990*)             HW_GPU_MODEL="Mali-G77 MP11";         HW_GPU_SCORE=68 ;;
            exynos9825*)            HW_GPU_MODEL="Mali-G76 MP12";         HW_GPU_SCORE=55 ;;
            *)                      HW_GPU_MODEL="Mali (unknown)";        HW_GPU_SCORE=40 ;;
        esac
        # Sysfs model override
        for p in /sys/class/misc/mali*/device/gpu_id \
                  /sys/class/misc/mali0/device/product_id; do
            [ -f "$p" ] && {
                local id; id=$(cat "$p" 2>/dev/null)
                [ -n "$id" ] && HW_GPU_MODEL="$HW_GPU_MODEL (id:$id)"
                break
            }
        done
        # Mali performance governor
        for p in /sys/class/misc/mali0/device/devfreq/*/governor; do
            [ -w "$p" ] && echo "performance" > "$p" 2>/dev/null && break
        done
    fi

    # ─── PowerVR / IMG ─────────────────────────────────────
    local vkdrv; vkdrv=$(getprop ro.hardware.vulkan 2>/dev/null || echo "")
    if echo "$vkdrv" | grep -qiE 'powervr|rogue|img'; then
        HW_GPU_VENDOR="imagination"; HW_GPU_MODEL="PowerVR Rogue"
        HW_GPU_SCORE=35; HW_GPU_NODE="/dev/pvr_sync"
    fi

    # ─── AMD Xclipse override via Vulkan prop ──────────────
    if echo "$vkdrv" | grep -qiE 'xclipse|amd|radeon'; then
        HW_GPU_VENDOR="amd"
        # Keep model from Mali detection above (already set)
        HW_GPU_SCORE=92
    fi

    # ─── Vulkan availability ───────────────────────────────
    # Check prop first, then library presence
    if [ -n "$vkdrv" ] || \
       [ -f /vendor/lib64/libvulkan.so ] || \
       [ -f /system/lib64/libvulkan.so ] || \
       command -v vulkaninfo >/dev/null 2>&1; then
        HW_GPU_VULKAN=1
    fi

    # ─── OpenCL availability ───────────────────────────────
    for p in /vendor/lib64/libOpenCL.so \
              /vendor/lib/libOpenCL.so   \
              /system/vendor/lib64/libOpenCL.so \
              /system/vendor/lib/libOpenCL.so   \
              /system/lib64/libOpenCL.so         \
              "$PREFIX/lib/libOpenCL.so"; do
        [ -f "$p" ] && { HW_GPU_OPENCL=1; break; }
    done
    # clinfo is definitive
    command -v clinfo >/dev/null 2>&1 && HW_GPU_OPENCL=1

    # If OpenCL available, switch hashcat to GPU mode
    [ "$HW_GPU_OPENCL" = 1 ] && HW_HASHCAT_DEVICE_TYPE=2
}

# ── NPU / DSP ────────────────────────────────────────────────
detect_npu() {
    HW_NPU_TYPE="none"; HW_NPU_AVAILABLE=0; HW_NPU_LABEL="—"

    # Qualcomm Hexagon DSP / CDSP / ADSP
    if ls /dev/adsprpc-smd /dev/cdsprpc-smd /dev/adsprpc \
          /dev/cdsp /dev/adsp 2>/dev/null | grep -q .; then
        HW_NPU_TYPE="hexagon-dsp"; HW_NPU_AVAILABLE=1
        HW_NPU_LABEL="Qualcomm Hexagon DSP"
    fi
    # Qualcomm NPU (newer devices)
    ls /dev/qcom-npu* /dev/npu* 2>/dev/null | grep -q . && {
        HW_NPU_TYPE="qualcomm-npu"; HW_NPU_AVAILABLE=1
        HW_NPU_LABEL="Qualcomm NPU"
    }
    # MediaTek APU / MDLA / VPU
    if ls /dev/mtk_mdla* /dev/mdla* /dev/vpu0 /dev/vpu1 2>/dev/null | grep -q . || \
       [ -d /sys/bus/platform/drivers/mtk-apu-core ]; then
        HW_NPU_TYPE="mediatek-apu"; HW_NPU_AVAILABLE=1
        HW_NPU_LABEL="MediaTek APU"
    fi
    # Samsung NPU
    ls /dev/npu_* 2>/dev/null | grep -q . && {
        HW_NPU_TYPE="samsung-npu"; HW_NPU_AVAILABLE=1
        HW_NPU_LABEL="Samsung NPU"
    }
}

# ── RAM ──────────────────────────────────────────────────────
detect_ram() {
    HW_RAM_TOTAL_MB=$(awk '/MemTotal/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null || echo 0)
    HW_RAM_AVAIL_MB=$(awk '/MemAvailable/{printf "%d",$2/1024}' /proc/meminfo 2>/dev/null || echo 0)
}

# ── Storage type ─────────────────────────────────────────────
detect_storage() {
    HW_STORAGE_TYPE="unknown"
    if [ -f /sys/block/sda/queue/rotational ]; then
        [ "$(cat /sys/block/sda/queue/rotational)" = 0 ] && HW_STORAGE_TYPE="UFS/NVMe" || HW_STORAGE_TYPE="HDD"
    elif ls /sys/block/mmcblk*/device/type 2>/dev/null | grep -q .; then
        HW_STORAGE_TYPE=$(cat /sys/block/mmcblk*/device/type 2>/dev/null | head -1 || echo eMMC)
    fi
}

# ── Thermal headroom ─────────────────────────────────────────
detect_thermal() {
    HW_THERMAL_OK=1; HW_THERMAL_HOTTEST=0
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$zone" ] || continue
        local t; t=$(cat "$zone" 2>/dev/null || echo 0)
        [ "${t:-0}" -gt "$HW_THERMAL_HOTTEST" ] 2>/dev/null && HW_THERMAL_HOTTEST=$t
    done
    # milliCelsius — above 45°C (45000) warn
    [ "${HW_THERMAL_HOTTEST:-0}" -gt 45000 ] 2>/dev/null && HW_THERMAL_OK=0
}

# ── Master runner ────────────────────────────────────────────
run_hardware_detection() {
    detect_cpu; detect_gpu; detect_npu; detect_ram; detect_storage; detect_thermal
}

# ── Build ranked accelerator label ──────────────────────────
rank_accelerators() {
    # Build the "best accelerator" summary for display
    HW_BEST_ACCEL="CPU (${HW_CPU_CORES}× ${HW_CPU_ARCH})"
    HW_ACCEL_SCORE=10

    if [ "$HW_GPU_SCORE" -gt "$HW_ACCEL_SCORE" ] 2>/dev/null; then
        HW_BEST_ACCEL="${HW_GPU_MODEL} [${HW_GPU_VENDOR}]"
        HW_ACCEL_SCORE=$HW_GPU_SCORE
        local apis=""
        [ "$HW_GPU_VULKAN"  = 1 ] && apis="${apis}Vulkan "
        [ "$HW_GPU_OPENCL"  = 1 ] && apis="${apis}OpenCL "
        [ -n "$apis" ] && HW_BEST_ACCEL="${HW_BEST_ACCEL}  (${apis% })"
    fi
    if [ "$HW_NPU_AVAILABLE" = 1 ]; then
        HW_BEST_ACCEL="${HW_BEST_ACCEL}  +  ${HW_NPU_LABEL}"
    fi
}

# ── Write the hardware profile env file ─────────────────────
write_hw_profile() {
    local prof="$HACKLAB_HOME/hw-profile.env"
    cat > "$prof" << HWEOF
# hacklab-v2 hardware profile — auto-generated by install.sh
# source this file in any script that needs hardware-aware flags

# ── CPU ──────────────────────────────────────────────────────
HW_CPU_ARCH="${HW_CPU_ARCH}"
HW_CPU_MODEL="${HW_CPU_MODEL}"
HW_CPU_CORES=${HW_CPU_CORES}
HW_CPU_BIG_CORES=${HW_CPU_BIG_CORES}
HW_CPU_LITTLE_CORES=${HW_CPU_LITTLE_CORES}
HW_CPU_MAX_MHZ=${HW_CPU_MAX_MHZ}
HW_CPU_HAS_NEON=${HW_CPU_HAS_NEON}
HW_CPU_HAS_SVE=${HW_CPU_HAS_SVE}
HW_CPU_HAS_SVE2=${HW_CPU_HAS_SVE2}
HW_CPU_HAS_AES=${HW_CPU_HAS_AES}
HW_CPU_HAS_SHA=${HW_CPU_HAS_SHA}
HW_CPU_HAS_CRC32=${HW_CPU_HAS_CRC32}
HW_CPU_HAS_FP16=${HW_CPU_HAS_FP16}
HW_CPU_HAS_DOTPROD=${HW_CPU_HAS_DOTPROD}
HW_CPU_HAS_I8MM=${HW_CPU_HAS_I8MM}
HW_OMP_THREADS=${HW_OMP_THREADS}

# ── GPU ──────────────────────────────────────────────────────
HW_GPU_VENDOR="${HW_GPU_VENDOR}"
HW_GPU_MODEL="${HW_GPU_MODEL}"
HW_GPU_NODE="${HW_GPU_NODE}"
HW_GPU_MAX_FREQ_MHZ=${HW_GPU_MAX_FREQ_MHZ}
HW_GPU_OPENCL=${HW_GPU_OPENCL}
HW_GPU_VULKAN=${HW_GPU_VULKAN}
HW_GPU_SCORE=${HW_GPU_SCORE}

# ── NPU / DSP ────────────────────────────────────────────────
HW_NPU_TYPE="${HW_NPU_TYPE}"
HW_NPU_AVAILABLE=${HW_NPU_AVAILABLE}
HW_NPU_LABEL="${HW_NPU_LABEL}"

# ── RAM ──────────────────────────────────────────────────────
HW_RAM_TOTAL_MB=${HW_RAM_TOTAL_MB}
HW_RAM_AVAIL_MB=${HW_RAM_AVAIL_MB}

# ── Storage ──────────────────────────────────────────────────
HW_STORAGE_TYPE="${HW_STORAGE_TYPE}"

# ── Derived tool flags ───────────────────────────────────────
# hashcat: 1=CPU-only  2=GPU(OpenCL)  3=CPU+GPU
HW_HASHCAT_DEVICE_TYPE=${HW_HASHCAT_DEVICE_TYPE}
# nmap: --min-parallelism value
HW_NMAP_PARALLEL=${HW_NMAP_PARALLEL}
# OMP/thread count for john, aircrack, etc.
export OMP_NUM_THREADS=${HW_OMP_THREADS}

# ── Best accelerator summary ─────────────────────────────────
HW_BEST_ACCEL="${HW_BEST_ACCEL}"
HW_ACCEL_SCORE=${HW_ACCEL_SCORE}
HWEOF
    chmod 644 "$prof"
}

# ════════════════════════════════════════════════════════════════
#  Hardware display report (runs after detection)
# ════════════════════════════════════════════════════════════════
print_hw_report() {
    # ── CPU box ─────────────────────────────────────────────
    box_top "CPU" "$C_CYAN"
    box_blank "$C_CYAN"
    box_line "  ${C_WHITE}Model   ${NC}${C_CYAN}${HW_CPU_MODEL}${NC}" "$C_CYAN"
    box_line "  ${C_WHITE}Arch    ${NC}${C_CYAN}${HW_CPU_ARCH}${NC}" "$C_CYAN"

    local core_str="${C_BGREEN}${HW_CPU_CORES} cores${NC}"
    if [ "${HW_CPU_BIG_CORES:-0}" -gt 0 ]; then
        core_str+="  ${DIM}(${HW_CPU_BIG_CORES} big + ${HW_CPU_LITTLE_CORES} little — big.LITTLE)${NC}"
    fi
    box_line "  ${C_WHITE}Cores   ${NC}$core_str" "$C_CYAN"
    [ "${HW_CPU_MAX_MHZ:-0}" -gt 0 ] && \
        box_line "  ${C_WHITE}Max clk ${NC}${C_BGREEN}${HW_CPU_MAX_MHZ} MHz${NC}" "$C_CYAN"

    # ISA feature badges
    local isa=""
    [ "$HW_CPU_HAS_NEON"    = 1 ] && isa+="${C_BGREEN}NEON${NC} "
    [ "$HW_CPU_HAS_SVE"     = 1 ] && isa+="${C_BGREEN}SVE${NC} "
    [ "$HW_CPU_HAS_SVE2"    = 1 ] && isa+="${C_BGREEN}SVE2${NC} "
    [ "$HW_CPU_HAS_AES"     = 1 ] && isa+="${C_BPURPLE}AES-HW${NC} "
    [ "$HW_CPU_HAS_SHA"     = 1 ] && isa+="${C_BPURPLE}SHA-HW${NC} "
    [ "$HW_CPU_HAS_DOTPROD" = 1 ] && isa+="${C_BCYAN}DOTPROD${NC} "
    [ "$HW_CPU_HAS_I8MM"    = 1 ] && isa+="${C_BCYAN}I8MM${NC} "
    [ "$HW_CPU_HAS_FP16"    = 1 ] && isa+="${C_CYAN}FP16${NC} "
    [ -n "$isa" ] && box_line "  ${C_WHITE}ISA     ${NC}${isa}" "$C_CYAN"
    box_blank "$C_CYAN"
    box_bottom "$C_CYAN"
    echo

    # ── GPU box ─────────────────────────────────────────────
    local gpu_color="$C_PURPLE"
    [ "$HW_GPU_SCORE" -ge 80 ] 2>/dev/null && gpu_color="$C_BPURPLE"
    [ "$HW_GPU_VENDOR" = "none" ] && gpu_color="$C_YELLOW"

    box_top "GPU / Graphics Accelerator" "$gpu_color"
    box_blank "$gpu_color"
    if [ "$HW_GPU_VENDOR" = "none" ]; then
        box_line "  ${C_YELLOW}⚠  GPU not detected via sysfs / device nodes${NC}" "$gpu_color"
    else
        box_line "  ${C_WHITE}Vendor  ${NC}${gpu_color}$(printf '%s' "$HW_GPU_VENDOR" | tr '[:lower:]' '[:upper:]')${NC}" "$gpu_color"
        box_line "  ${C_WHITE}Model   ${NC}${C_BPURPLE}${HW_GPU_MODEL}${NC}" "$gpu_color"
        [ -n "$HW_GPU_NODE" ] && \
            box_line "  ${C_WHITE}Device  ${NC}${DIM}${HW_GPU_NODE}${NC}" "$gpu_color"
        [ "${HW_GPU_MAX_FREQ_MHZ:-0}" -gt 0 ] && \
            box_line "  ${C_WHITE}Max clk ${NC}${C_BPURPLE}${HW_GPU_MAX_FREQ_MHZ} MHz${NC}" "$gpu_color"

        # Compute API badges
        local apis=""
        [ "$HW_GPU_VULKAN" = 1 ] && apis+="${C_BPURPLE}▶ Vulkan${NC}  "
        [ "$HW_GPU_OPENCL" = 1 ] && apis+="${C_BCYAN}▶ OpenCL${NC}  "
        [ -n "$apis" ] && box_line "  ${C_WHITE}Compute ${NC}${apis}" "$gpu_color"
        [ -z "$apis" ] && box_line "  ${C_YELLOW}⚠  No OpenCL/Vulkan compute detected${NC}" "$gpu_color"

        # Accel score bar
        local score_fill=$(( HW_GPU_SCORE * 20 / 100 ))
        local score_empty=$(( 20 - score_fill ))
        local score_bar="${C_BGREEN}"
        [ "$HW_GPU_SCORE" -lt 60 ] 2>/dev/null && score_bar="${C_YELLOW}"
        [ "$HW_GPU_SCORE" -lt 40 ] 2>/dev/null && score_bar="${C_RED}"
        local bar="${score_bar}"; bar+=$(printf '█%.0s' $(seq 1 $score_fill))
        bar+="${DIM}$(printf '░%.0s' $(seq 1 $score_empty))${NC}"
        box_line "  ${C_WHITE}Score   ${NC}${bar}  ${C_WHITE}${HW_GPU_SCORE}/100${NC}" "$gpu_color"
    fi
    box_blank "$gpu_color"
    box_bottom "$gpu_color"
    echo

    # ── NPU box ─────────────────────────────────────────────
    local npu_color="$C_ORANGE"
    box_top "NPU / AI Accelerator" "$npu_color"
    box_blank "$npu_color"
    if [ "$HW_NPU_AVAILABLE" = 1 ]; then
        box_line "  ${C_BGREEN}✓${NC}  ${C_BORNG}${HW_NPU_LABEL}${NC}  detected" "$npu_color"
        box_line "  ${DIM}Type: ${HW_NPU_TYPE}${NC}" "$npu_color"
    else
        box_line "  ${DIM}No dedicated NPU/DSP detected — CPU handles inference${NC}" "$npu_color"
    fi
    box_blank "$npu_color"
    box_bottom "$npu_color"
    echo

    # ── RAM / Thermal box ────────────────────────────────────
    box_top "Memory · Storage · Thermal" "$C_CYAN"
    box_blank "$C_CYAN"
    box_line "  ${C_WHITE}RAM total   ${NC}${C_BGREEN}${HW_RAM_TOTAL_MB} MB${NC}" "$C_CYAN"
    box_line "  ${C_WHITE}RAM free    ${NC}${C_CYAN}${HW_RAM_AVAIL_MB} MB${NC}" "$C_CYAN"
    box_line "  ${C_WHITE}Storage     ${NC}${C_CYAN}${HW_STORAGE_TYPE}${NC}" "$C_CYAN"
    if [ "${HW_THERMAL_OK:-1}" = 1 ]; then
        box_line "  ${C_WHITE}Thermal     ${NC}${C_BGREEN}✓ normal${NC}" "$C_CYAN"
    else
        local hot_c=$(( ${HW_THERMAL_HOTTEST:-0} / 1000 ))
        box_line "  ${C_WHITE}Thermal     ${NC}${C_RED}⚠ ${hot_c}°C — device is warm, throttling possible${NC}" "$C_CYAN"
    fi
    box_blank "$C_CYAN"
    box_bottom "$C_CYAN"
    echo

    # ── Active accelerator summary ───────────────────────────
    local acc_color="$C_BGREEN"
    [ "$HW_GPU_VENDOR" = "none" ] && acc_color="$C_YELLOW"
    box_top "Active Accelerator Profile" "$acc_color"
    box_blank "$acc_color"
    box_line "  ${C_WHITE}Best accel  ${NC}${C_BGREEN}${HW_BEST_ACCEL}${NC}" "$acc_color"
    box_line "  ${C_WHITE}nmap        ${NC}${DIM}--min-parallelism ${HW_NMAP_PARALLEL} -T4${NC}" "$acc_color"
    box_line "  ${C_WHITE}hashcat     ${NC}${DIM}--opencl-device-types ${HW_HASHCAT_DEVICE_TYPE}${NC}" "$acc_color"
    box_line "  ${C_WHITE}john / OMP  ${NC}${DIM}OMP_NUM_THREADS=${HW_OMP_THREADS}${NC}" "$acc_color"
    box_blank "$acc_color"
    box_line "  ${DIM}Profile written → \$HACKLAB_HOME/hw-profile.env${NC}" "$acc_color"
    box_blank "$acc_color"
    box_bottom "$acc_color"
}

# ════════════════════════════════════════════════════════════════
#  PHASE 0 · BANNER
# ════════════════════════════════════════════════════════════════
clear
printf "${C_BCYAN}"
cat << 'BANNER'

  ██╗  ██╗ █████╗  ██████╗██╗  ██╗██╗      █████╗ ██████╗
  ██║  ██║██╔══██╗██╔════╝██║ ██╔╝██║     ██╔══██╗██╔══██╗
  ███████║███████║██║     █████╔╝ ██║     ███████║██████╔╝
  ██╔══██║██╔══██║██║     ██╔═██╗ ██║     ██╔══██║██╔══██╗
  ██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██║  ██║██████╔╝
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝

BANNER
printf "${NC}"

box_top "hacklab-v2 installer" "$C_PURPLE"
box_blank "$C_PURPLE"
if [ "$UPGRADE" = 1 ]; then
    box_line "  Mode  :  ${C_YELLOW}UPGRADE${NC}" "$C_PURPLE"
else
    box_line "  Mode  :  ${C_BGREEN}FRESH INSTALL${NC}" "$C_PURPLE"
fi
box_line "  Target:  ${C_CYAN}$HACKLAB_HOME${NC}" "$C_PURPLE"
box_line "  Real service graph · GPU-aware · TUI + web dashboards" "$C_PURPLE"
box_blank "$C_PURPLE"
box_bottom "$C_PURPLE"
echo; sleep 0.4

# ════════════════════════════════════════════════════════════════
#  PHASE 1 · HARDWARE DETECTION
# ════════════════════════════════════════════════════════════════
section "hardware detection & accelerator profile"

printf "  ${C_CYAN}⠿${NC}  Scanning CPU, GPU, NPU, RAM, thermal…\n"
[ -t 1 ] && spin_start "probing hardware subsystems"
run_hardware_detection
rank_accelerators
[ -t 1 ] && spin_stop

echo; print_hw_report

# Write profile (needed before core so modules can include it)
write_hw_profile
record "hw-probe" ok "${HW_CPU_CORES}c ${HW_CPU_ARCH}"
record "hw-profile" ok "written to hw-profile.env"
PROG_DONE=$((PROG_DONE+2))   # 2 internal steps: scan + write

# ════════════════════════════════════════════════════════════════
#  PHASE 2 · CORE INSTALL
# ════════════════════════════════════════════════════════════════
section "core install"
box_top "staging hacklab tree" "$C_CYAN"
box_blank

mkdir -p "$HACKLAB_HOME/services" "$HACKLAB_HOME/core" "$HACKLAB_HOME/modules" \
         "$HACKLAB_HOME/src/webdash" "$HACKLAB_HOME/bin"

tick "core-services"  "service definitions"    cp -r "$HERE/services/."  "$HACKLAB_HOME/services/"
tick "core-tui"       "TUI core"               cp -r "$HERE/core/."      "$HACKLAB_HOME/core/"
tick "core-modules"   "tool modules"           cp -r "$HERE/modules/."   "$HACKLAB_HOME/modules/"
tick "core-webdash"   "web dashboard"          cp -r "$HERE/webdash/."   "$HACKLAB_HOME/src/webdash/"
tick "core-bin"       "launcher source"        cp -r "$HERE/bin/."       "$HACKLAB_HOME/bin/"
tick "core-perms"     "exec permissions"       chmod +x \
        "$HACKLAB_HOME/core/"*.sh \
        "$HACKLAB_HOME/modules/"*.sh \
        "$HACKLAB_HOME/lib/"*.sh \
        "$HACKLAB_HOME/bin/"*
tick "core-svc-perms" "service script perms"   bash -c \
        'find "$1/services" \( -name run -o -name healthcheck \) | xargs -r chmod +x' \
        _ "$HACKLAB_HOME"
tick "launcher"       "hacklab on PATH"        ln -sf \
        "$HACKLAB_HOME/bin/hacklab" "$PREFIX/bin/hacklab"

if [ "${STEP_STATUS[launcher]}" = "fail" ]; then
    printf "  ${C_YELLOW}⚠${NC}  symlink failed — run directly: ${C_CYAN}%s${NC}\n" \
        "$HACKLAB_HOME/bin/hacklab"
fi

box_blank; box_bottom
bail_if_critical_failed

# ════════════════════════════════════════════════════════════════
#  PHASE 3 · MODERN TOOLING  (+ GPU compute packages)
# ════════════════════════════════════════════════════════════════
section "modern tooling"
box_top "packages + interactive tools" "$C_CYAN"
box_blank

step "curl" "curl" -- bash -c \
    "source '$HACKLAB_HOME/lib/common.sh' >/dev/null 2>&1; install_pkg_quiet curl"
step "zip" "zip" -- bash -c \
    "source '$HACKLAB_HOME/lib/common.sh' >/dev/null 2>&1; install_pkg_quiet zip"

echo; printf "  ${DIM}bootstrapping interactive UI tools…${NC}\n"; echo
bootstrap_tool "gum"  "gum"  ensure_gum  gum  --version
[ "${STEP_STATUS[gum]}" = "ok" ] && HAVE_GUM=1
bootstrap_tool "fzf"  "fzf"  ensure_fzf  fzf  --version
bootstrap_tool "tmux" "tmux" ensure_tmux tmux -V

# ── GPU compute tools based on detected hardware ─────────────
echo
box_divider "$C_CYAN"
printf "  ${C_BPURPLE}▸ GPU compute packages${NC}  "
if [ "$HW_GPU_OPENCL" = 1 ]; then
    printf "${C_BGREEN}OpenCL detected — installing compute tools${NC}\n"
    step "clinfo" "clinfo (OpenCL info)" -- bash -c \
        "source '$HACKLAB_HOME/lib/common.sh' >/dev/null 2>&1; install_pkg_quiet clinfo"
    # hashcat with OpenCL GPU cracking
    step "hashcat" "hashcat (GPU cracking)" -- bash -c \
        "source '$HACKLAB_HOME/lib/common.sh' >/dev/null 2>&1; install_pkg_quiet hashcat"
else
    printf "${C_YELLOW}no OpenCL — skipping GPU compute tools${NC}\n"
    record "clinfo"   skip "no OpenCL detected"
    record "hashcat"  skip "no OpenCL — CPU fallback via john"
    PROG_DONE=$((PROG_DONE+2))   # count skipped manually
fi

if [ "$HW_GPU_VULKAN" = 1 ]; then
    printf "\n  ${C_BPURPLE}▸ Vulkan detected${NC} — ${DIM}GPU-accelerated rendering/compute available${NC}\n"
fi

box_blank; box_bottom

# ════════════════════════════════════════════════════════════════
#  PHASE 4 · ROOT DETECTION
# ════════════════════════════════════════════════════════════════
section "root detection"
ROOTED=0
box_top "checking su / Magisk access" "$C_CYAN"
box_blank
if has_root; then
    ROOTED=1
    box_line "  ${C_BGREEN}✓  root access confirmed${NC}" "$C_CYAN"
else
    box_line "  ${C_YELLOW}⚠  no root — no-root sandbox path${NC}" "$C_CYAN"
fi
PROG_DONE=$((PROG_DONE+1))
box_blank; box_bottom

# ════════════════════════════════════════════════════════════════
#  PHASE 5 · BOOT-TIME PATH
# ════════════════════════════════════════════════════════════════
section "boot-time path"
box_top "boot configuration" "$C_CYAN"
box_blank
box_line "  ${C_WHITE}1)${NC}  no-root  — Termux:Boot trigger" "$C_CYAN"
[ "$ROOTED" = 1 ] && \
box_line "  ${C_WHITE}2)${NC}  root     — Magisk module + chroot" "$C_CYAN"
box_line "  ${C_WHITE}3)${NC}  both" "$C_CYAN"
box_blank; box_bottom; echo

path_choice=""
if [ "$HAVE_GUM" = 1 ]; then
    opts=("1) no-root — Termux:Boot")
    [ "$ROOTED" = 1 ] && opts+=("2) root — Magisk module")
    opts+=("3) both")
    pick="$(printf '%s\n' "${opts[@]}" | gum choose --header "  boot path:")"
    case "$pick" in 1\)*) path_choice=1;; 2\)*) path_choice=2;; 3\)*) path_choice=3;; esac
else
    printf "  ${C_WHITE}${BOLD}Choose [1-3]:${NC} "; read -r path_choice
fi

setup_noroot() {
    mkdir -p "$HOME/.termux/boot"; echo
    box_top "no-root boot setup" "$C_GREEN"; box_blank
    tick "boot-noroot" "Termux:Boot trigger" \
        cp "$HERE/boot/noroot/hacklab-boot" "$HOME/.termux/boot/hacklab-boot"
    chmod +x "$HOME/.termux/boot/hacklab-boot" 2>/dev/null
    box_blank; box_divider "$C_GREEN"
    box_line "  ${C_YELLOW}Manual steps (Android restriction):${NC}" "$C_GREEN"
    box_blank
    box_line "  ${C_WHITE}1.${NC}  Install Termux:Boot from F-Droid / GitHub" "$C_GREEN"
    box_line "  ${C_WHITE}2.${NC}  Open it once (Android holds it 'stopped')" "$C_GREEN"
    box_line "  ${C_WHITE}3.${NC}  Disable battery optimization for Termux + Boot" "$C_GREEN"
    box_blank; box_bottom "$C_GREEN"
}

setup_root() {
    echo; box_top "root / Magisk module setup" "$C_PURPLE"; box_blank
    local pkgdir="$HACKLAB_HOME/magisk-pkg"
    rm -rf "$pkgdir"; mkdir -p "$pkgdir/hacklab-src"
    cp -r "$HERE/boot/root/." "$pkgdir/"
    cp -r "$HERE/lib" "$HERE/services" "$HERE/bin" "$pkgdir/hacklab-src/"
    local zipfile="$HACKLAB_HOME/hacklab-root-module.zip"
    step "boot-root" "Magisk module packaged" -- \
        bash -c "cd '$pkgdir' && zip -r -q '$zipfile' ."
    if [ "${STEP_STATUS[boot-root]}" = "ok" ]; then
        box_blank
        box_line "  ${C_BGREEN}✓  packaged:${NC}  ${C_CYAN}${zipfile}${NC}" "$C_PURPLE"
        box_blank; box_divider "$C_PURPLE"
        box_line "  ${C_YELLOW}Manual step:${NC}" "$C_PURPLE"
        box_line "  Magisk → Modules → Install from storage → zip → reboot" "$C_PURPLE"
    fi
    box_blank; box_bottom "$C_PURPLE"
}

case "$path_choice" in
    1) setup_noroot ;;
    2) [ "$ROOTED" = 1 ] && setup_root || {
            printf "  ${C_RED}✗${NC} root not available\n"
            record "boot-root" fail "root not available"; } ;;
    3) setup_noroot; setup_root ;;
    *) printf "  ${C_YELLOW}⚠${NC}  skipping — re-run install.sh to configure later\n"
       record "boot-path" skip "no choice" ;;
esac

# ════════════════════════════════════════════════════════════════
#  PHASE 6 · ANIMATED SUMMARY
# ════════════════════════════════════════════════════════════════
section "installation summary"
sleep 0.2; echo

ELAPSED=$(( $(date +%s) - INSTALL_START ))
ok_n=0; fail_n=0; skip_n=0
for key in "${STEP_ORDER[@]}"; do
    case "${STEP_STATUS[$key]}" in
        ok)   ok_n=$((ok_n+1))   ;;
        fail) fail_n=$((fail_n+1)) ;;
        skip) skip_n=$((skip_n+1)) ;;
    esac
done

SUM_COLOR="$C_BGREEN"
[ "$fail_n" -gt 0 ] && SUM_COLOR="$C_YELLOW"
critical_failed && SUM_COLOR="$C_BRED"

box_top "results" "$SUM_COLOR"; box_blank "$SUM_COLOR"

for key in "${STEP_ORDER[@]}"; do
    local_status="${STEP_STATUS[$key]}"
    local_detail="${STEP_DETAIL[$key]}"
    case "$local_status" in
        ok)   icon="${C_BGREEN}✓${NC}"; col="$C_BGREEN" ;;
        fail) icon="${C_BRED}✗${NC}";  col="$C_RED"    ;;
        skip) icon="${C_YELLOW}–${NC}"; col="$C_YELLOW" ;;
    esac
    local_text="  ${icon}  ${col}$(printf '%-22s' "$key")${NC}"
    [ -n "$local_detail" ] && local_text+="  ${DIM}${local_detail}${NC}"
    printf "${SUM_COLOR}│${NC} "; printf '%b' "$local_text"
    vis=$(printf '%b' "$local_text" | sed 's/\x1b\[[0-9;]*[mK]//g')
    pad=$(( BOX_W - ${#vis} - 2 )); [ $pad -lt 0 ] && pad=0
    printf '%*s' $pad ''; printf " ${SUM_COLOR}│${NC}\n"; sleep 0.08
done

box_blank "$SUM_COLOR"; box_divider "$SUM_COLOR"
stats="  ${C_BGREEN}${ok_n} ok${NC}  ${C_RED}${fail_n} failed${NC}  ${C_YELLOW}${skip_n} skipped${NC}  ${DIM}${ELAPSED}s${NC}"
printf "${SUM_COLOR}│${NC} "; printf '%b' "$stats"
vis=$(printf '%b' "$stats" | sed 's/\x1b\[[0-9;]*[mK]//g')
pad=$(( BOX_W - ${#vis} - 2 )); [ $pad -lt 0 ] && pad=0
printf '%*s' $pad ''; printf " ${SUM_COLOR}│${NC}\n"
box_blank "$SUM_COLOR"; box_bottom "$SUM_COLOR"

# ════════════════════════════════════════════════════════════════
#  PHASE 7 · VERDICT + NEXT STEPS
# ════════════════════════════════════════════════════════════════
echo; bail_if_critical_failed

if [ "$fail_n" -gt 0 ]; then
    printf "\n  ${C_YELLOW}${BOLD}⚠  installed with %d warning(s)${NC}  — core works\n" "$fail_n"
else
    printf "\n  ${C_BGREEN}${BOLD}✓  hacklab-v2 installed cleanly!${NC}\n"
fi

echo
box_top "next steps" "$C_BCYAN"; box_blank "$C_BCYAN"
box_line "  ${C_WHITE}▸ Start ALL services now:${NC}" "$C_BCYAN"
box_line "    ${C_CYAN}bash ~/.hacklab/lib/svc-engine.sh up${NC}" "$C_BCYAN"
box_line "  ${C_WHITE}▸ Stop ALL services:${NC}" "$C_BCYAN"
box_line "    ${C_CYAN}bash ~/.hacklab/lib/svc-engine.sh down${NC}" "$C_BCYAN"
box_blank "$C_BCYAN"
box_line "  ${C_WHITE}▸ One service${NC} ${DIM}(dropbear / metrics / webdash):${NC}" "$C_BCYAN"
box_line "    ${C_CYAN}svc-engine.sh {start|stop|restart|logs} <name>${NC}" "$C_BCYAN"
box_line "    ${DIM}prefix: bash ~/.hacklab/lib/${NC}  ${DIM}— or just 'hacklab' → Service control${NC}" "$C_BCYAN"
box_blank "$C_BCYAN"
box_line "  ${C_WHITE}▸ TUI dashboard / modules:${NC}" "$C_BCYAN"
box_line "    ${C_CYAN}hacklab${NC}" "$C_BCYAN"
box_blank "$C_BCYAN"
box_line "  ${C_WHITE}▸ Web panel:${NC}  ${C_CYAN}http://127.0.0.1:8080${NC}" "$C_BCYAN"
box_blank "$C_BCYAN"
box_line "  ${C_WHITE}▸ Desktop (optional):${NC}  hacklab → tool modules → gui-x11" "$C_BCYAN"
box_line "    ${DIM}light style (xfce/lxqt/i3) or a full distro — Kali, Ubuntu,${NC}" "$C_BCYAN"
box_line "    ${DIM}Debian, Arch, Fedora, openSUSE, Alpine — via proot-distro${NC}" "$C_BCYAN"
box_blank "$C_BCYAN"
box_line "  ${C_WHITE}▸ Active accelerator:${NC}" "$C_BCYAN"
box_line "    ${C_BPURPLE}${HW_BEST_ACCEL}${NC}" "$C_BCYAN"
box_blank "$C_BCYAN"
box_line "  ${DIM}hw-profile.env auto-loaded by all modules${NC}" "$C_BCYAN"
box_blank "$C_BCYAN"
box_line "  ${C_WHITE}▸ Update later${NC} ${DIM}(if cloned via git):${NC}" "$C_BCYAN"
box_line "    ${C_CYAN}cd Hacklab-v2 && git pull && bash install.sh${NC}" "$C_BCYAN"
box_blank "$C_BCYAN"; box_bottom "$C_BCYAN"
echo
