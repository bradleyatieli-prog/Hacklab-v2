#!/data/data/com.termux/files/usr/bin/bash
# ════════════════════════════════════════════════════════════════
#  hacklab-v2 / lib/hw.sh
#  Hardware profile loader — source this at the top of any script
#  that needs hardware-aware flags.
#
#  Provides: HW_* variables + hw_apply_cpu_governor()
#                            + hw_apply_gpu_governor()
#                            + hw_best_hashcat_args()
#                            + hw_best_nmap_args()
# ════════════════════════════════════════════════════════════════
HACKLAB_HOME="${HACKLAB_HOME:-$HOME/.hacklab}"
HW_PROFILE="$HACKLAB_HOME/hw-profile.env"

# Load the profile written by install.sh
if [ -f "$HW_PROFILE" ]; then
    # shellcheck source=/dev/null
    source "$HW_PROFILE"
else
    # Safe defaults if profile not yet written
    HW_CPU_CORES=$(nproc 2>/dev/null || echo 4)
    HW_CPU_BIG_CORES=0; HW_CPU_LITTLE_CORES=0
    HW_CPU_HAS_NEON=0; HW_CPU_HAS_AES=0; HW_CPU_HAS_SHA=0
    HW_GPU_VENDOR="none"; HW_GPU_MODEL="none"
    HW_GPU_OPENCL=0; HW_GPU_VULKAN=0; HW_GPU_SCORE=0
    HW_NPU_AVAILABLE=0; HW_NPU_LABEL="—"
    HW_RAM_TOTAL_MB=0; HW_RAM_AVAIL_MB=0
    HW_HASHCAT_DEVICE_TYPE=1
    HW_NMAP_PARALLEL=16
    HW_OMP_THREADS=$HW_CPU_CORES
    HW_BEST_ACCEL="CPU (fallback)"
    export OMP_NUM_THREADS=$HW_OMP_THREADS
fi

# ── Try to set CPU governor to performance ──────────────────
hw_apply_cpu_governor() {
    local gov="${1:-performance}"
    local applied=0
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -w "$cpu" ] && { echo "$gov" > "$cpu" 2>/dev/null && applied=1; }
    done
    return $([ $applied -eq 1 ] && echo 0 || echo 1)
}

# ── Try to set GPU governor ─────────────────────────────────
hw_apply_gpu_governor() {
    local gov="${1:-performance}"
    # Adreno (kgsl)
    for p in /sys/class/kgsl/kgsl-3d0/devfreq/governor \
              /sys/bus/platform/drivers/kgsl/*/devfreq/governor; do
        [ -w "$p" ] && echo "$gov" > "$p" 2>/dev/null
    done
    # Mali
    for p in /sys/class/misc/mali*/device/devfreq/*/governor; do
        [ -w "$p" ] && echo "$gov" > "$p" 2>/dev/null
    done
    # Lock Adreno to lowest power level (= highest perf)
    [ -w /sys/class/kgsl/kgsl-3d0/min_pwrlevel ] && \
        echo "0" > /sys/class/kgsl/kgsl-3d0/min_pwrlevel 2>/dev/null
}

# ── Build optimal hashcat argument string ───────────────────
# Usage: eval "$(hw_best_hashcat_args)"
# Sets $HW_HC_ARGS ready to append to any hashcat command
hw_best_hashcat_args() {
    local args="--opencl-device-types ${HW_HASHCAT_DEVICE_TYPE}"
    args+=" --workload-profile 3"   # high performance
    [ "${HW_GPU_OPENCL:-0}" = 1 ] && args+=" --force"
    echo "HW_HC_ARGS='${args}'"
}

# ── Build optimal nmap argument string ──────────────────────
hw_best_nmap_args() {
    local args="-T4 --min-parallelism ${HW_NMAP_PARALLEL}"
    args+=" --min-rate 1000"
    echo "HW_NMAP_ARGS='${args}'"
}

# ── Print a one-liner hardware summary ──────────────────────
hw_print_summary() {
    local GREEN='\033[0;32m' CYAN='\033[0;36m' NC='\033[0m' DIM='\033[2m'
    printf "${CYAN}[hw]${NC} %s\n" "$HW_BEST_ACCEL"
    printf "${CYAN}[hw]${NC} CPU: ${HW_CPU_CORES} cores"
    [ "${HW_CPU_BIG_CORES:-0}" -gt 0 ] && printf " (${HW_CPU_BIG_CORES}B+${HW_CPU_LITTLE_CORES}L)"
    [ "${HW_CPU_HAS_NEON:-0}" = 1 ] && printf " NEON"
    [ "${HW_CPU_HAS_AES:-0}"  = 1 ] && printf " AES-HW"
    [ "${HW_CPU_HAS_SHA:-0}"  = 1 ] && printf " SHA-HW"
    printf "\n"
    [ "${HW_GPU_SCORE:-0}" -gt 0 ] && \
        printf "${CYAN}[hw]${NC} GPU: ${HW_GPU_MODEL} [score:${HW_GPU_SCORE}/100]"
    [ "${HW_GPU_OPENCL:-0}" = 1 ] && printf " OpenCL✓"
    [ "${HW_GPU_VULKAN:-0}" = 1 ] && printf " Vulkan✓"
    [ "${HW_GPU_SCORE:-0}" -gt 0 ] && printf "\n"
    [ "${HW_NPU_AVAILABLE:-0}" = 1 ] && \
        printf "${CYAN}[hw]${NC} NPU: ${HW_NPU_LABEL}\n"
    printf "${DIM}     OMP_NUM_THREADS=${HW_OMP_THREADS}  hashcat-device=${HW_HASHCAT_DEVICE_TYPE}  nmap-parallel=${HW_NMAP_PARALLEL}${NC}\n"
}
