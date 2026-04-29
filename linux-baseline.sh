#!/usr/bin/env bash
#
# linux-baseline.sh — Capture a portable system + kernel baseline and a small
# set of microbenchmarks, into a single text file suitable for diffing between
# machines or kernel versions.
#
# Why this exists:
#   - Reproducible, dependency-light snapshot: only requires bash + coreutils +
#     openssl. Everything else (sysbench, fio, hdparm, ethtool) is probed and
#     used opportunistically with graceful fallbacks.
#   - Output is structured as `key=value` pairs under markdown section headers
#     so two reports diff cleanly (`diff -u a.txt b.txt`).
#   - Probes Linux 7.0-era kernel surface (Rust, AccECN, BPF LSM, io_uring,
#     XFS self-healing, module sig hash) so cross-kernel comparisons are
#     meaningful, not just hardware comparisons.
#
# Usage:
#   ./linux-baseline.sh [output-dir]
#
# Environment overrides (all optional):
#   BASELINE_DD_MB=1024         Disk benchmark file size in MB.
#   BASELINE_CPU_SECONDS=5      Seconds per single-thread CPU bench run.
#   BASELINE_MEM_GB=8           Memory bandwidth probe size in GB.
#   BASELINE_BENCH_DIR=/path    Force disk bench directory (must NOT be tmpfs).
#
# Exit codes:
#   0  success (report written)
#   1  fatal precondition failure (no writable output dir, etc.)
#
set -euo pipefail
IFS=$'\n\t'

readonly VERSION="1.0"
readonly DD_MB="${BASELINE_DD_MB:-1024}"
readonly CPU_SECONDS="${BASELINE_CPU_SECONDS:-5}"
readonly MEM_GB="${BASELINE_MEM_GB:-8}"

# Argument: optional output directory.
case "${1:-}" in
  -h|--help)
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac
OUT_DIR="${1:-${BASELINE_OUT_DIR:-$PWD}}"
HOST="$(hostname -s 2>/dev/null || hostname)"
STAMP="$(date -u +%Y%m%d-%H%M%SZ)"
OUT_FILE="${OUT_DIR%/}/baseline-${HOST}-${STAMP}.txt"

mkdir -p "$OUT_DIR" || { echo "Cannot create $OUT_DIR" >&2; exit 1; }
: > "$OUT_FILE" || { echo "Cannot write $OUT_FILE" >&2; exit 1; }

readonly OUT_FILE
START_EPOCH=$(date +%s)
BENCH_FILE=""
trap '[[ -n "$BENCH_FILE" && -f "$BENCH_FILE" ]] && rm -f "$BENCH_FILE"' EXIT

# ---- helpers ----------------------------------------------------------------

have()    { command -v "$1" >/dev/null 2>&1; }
status()  { printf '[*] %s\n' "$*" >&2; }
report()  { printf '%s\n' "$*" >> "$OUT_FILE"; }
section() { report ""; report "## $1"; report ""; }
kv()      { report "$1=$2"; }

# Capture a command's combined output into a fenced block in the report.
# Failure is non-fatal (the surrounding script continues).
run_capture() {
  local label="$1"; shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  report "### $label"
  report '```'
  printf '%s\n' "${out:-(no output)}" >> "$OUT_FILE"
  report '```'
  if [[ $rc -ne 0 ]]; then
    kv "${label}_exit_status" "$rc"
  fi
}

# Pull a single CONFIG_FOO line value from the running kernel's config.
# Looks at /proc/config.gz first (IKCONFIG), then /boot/config-$(uname -r).
# Returns empty string if not available.
probe_config() {
  local key="$1" line=""
  if [[ -r /proc/config.gz ]]; then
    line="$(zcat /proc/config.gz 2>/dev/null | grep "^${key}=" | head -1)"
  elif [[ -r "/boot/config-$(uname -r)" ]]; then
    line="$(grep "^${key}=" "/boot/config-$(uname -r)" | head -1)"
  fi
  [[ -n "$line" ]] && printf '%s' "${line#*=}"
}

# Pick the first non-tmpfs writable directory for disk benchmarks.
# tmpfs would just measure RAM bandwidth and pollute disk numbers.
pick_bench_dir() {
  if [[ -n "${BASELINE_BENCH_DIR:-}" ]]; then
    printf '%s' "$BASELINE_BENCH_DIR"; return
  fi
  local d fst
  for d in "$PWD" "$HOME" /var/tmp; do
    [[ -d "$d" && -w "$d" ]] || continue
    fst="$(findmnt -no FSTYPE --target "$d" 2>/dev/null || true)"
    [[ "$fst" == "tmpfs" ]] && continue
    printf '%s' "$d"; return
  done
}

# ---- header ------------------------------------------------------------------

report "# Linux Baseline Report"
kv "report_version"   "$VERSION"
kv "host"             "$(hostname)"
kv "generated_utc"    "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
kv "generated_local"  "$(date +%Y-%m-%dT%H:%M:%S%z)"
kv "boot_id"          "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
kv "out_file"         "$OUT_FILE"

# ---- 1. system identity ------------------------------------------------------
section "1. System Identity"
status "system identity"

kv "uname"            "$(uname -srvmo)"
kv "kernel"           "$(uname -r)"
kv "arch"             "$(uname -m)"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  kv "distro"         "${PRETTY_NAME:-${NAME:-unknown}}"
  kv "distro_id"      "${ID:-unknown}"
  kv "distro_version" "${VERSION_ID:-unknown}"
fi
kv "uptime_seconds"   "$(awk '{print int($1)}' /proc/uptime)"
[[ -d /sys/firmware/efi ]] && kv "boot_mode" "UEFI" || kv "boot_mode" "BIOS"

# Best-effort vendor/product from sysfs DMI (no root needed).
for f in sys_vendor product_name product_version board_name; do
  [[ -r "/sys/class/dmi/id/$f" ]] && kv "dmi_$f" "$(<"/sys/class/dmi/id/$f")"
done

# Distro package versions of kernel (helps catch downgrades).
if have pacman; then
  kv "pkg_kernel" "$(pacman -Q linux 2>/dev/null || true)"
elif have dpkg; then
  kv "pkg_kernel" "$(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/ {print $2,$3}' | head -1)"
elif have rpm; then
  kv "pkg_kernel" "$(rpm -q kernel 2>/dev/null | head -1)"
fi

# ---- 2. kernel & boot --------------------------------------------------------
section "2. Kernel & Boot"
status "kernel & boot"

kv "kernel_build"     "$(uname -v)"
kv "kernel_cmdline"   "$(tr -d '\n' </proc/cmdline)"
kv "preempt_model"    "$(grep -oE 'PREEMPT_(RT|DYNAMIC|VOLUNTARY|NONE)' /proc/version | head -1 || echo unknown)"
kv "tainted"          "$(cat /proc/sys/kernel/tainted 2>/dev/null || echo n/a)"

if have systemd-analyze; then
  sa="$(systemd-analyze 2>/dev/null | head -1 || true)"
  [[ -n "$sa" ]] && kv "boot_total" "$sa"
fi

# ---- 3. CPU ------------------------------------------------------------------
section "3. CPU"
status "CPU"

if have lscpu; then
  run_capture "lscpu" lscpu
  while IFS=: read -r k v; do
    v="${v#"${v%%[![:space:]]*}"}"
    case "$k" in
      "Architecture"|"Model name"|"Vendor ID"|"CPU(s)"|"Thread(s) per core"|\
      "Core(s) per socket"|"Socket(s)"|"NUMA node(s)"|"CPU max MHz"|"CPU min MHz"|\
      "Virtualization"|"L1d cache"|"L2 cache"|"L3 cache"|"BogoMIPS")
        key="cpu_$(printf '%s' "$k" | tr '[:upper:] ()' '[:lower:]_' | tr -s '_' )"
        kv "$key" "$v"
        ;;
    esac
  done < <(lscpu)
fi

# Frequency / governor / driver — these change perceived "snappiness".
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
  kv "cpu_governor" "$(<"/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")"
fi
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver ]]; then
  kv "cpu_scaling_driver" "$(<"/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver")"
fi
if [[ -r /sys/devices/system/cpu/intel_pstate/status ]]; then
  kv "intel_pstate" "$(</sys/devices/system/cpu/intel_pstate/status)"
fi
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]]; then
  kv "epp" "$(<"/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference")"
fi
[[ -r /sys/devices/system/cpu/smt/active ]] && kv "smt_active" "$(</sys/devices/system/cpu/smt/active)"
[[ -r /proc/cpuinfo ]] && kv "microcode" "$(awk -F': ' '/microcode/ {print $2; exit}' /proc/cpuinfo)"

# Mitigations status — affects benchmark numbers a lot, must capture.
if [[ -d /sys/devices/system/cpu/vulnerabilities ]]; then
  for v in /sys/devices/system/cpu/vulnerabilities/*; do
    kv "vuln_$(basename "$v")" "$(<"$v")"
  done
fi

# ---- 4. Memory ---------------------------------------------------------------
section "4. Memory"
status "Memory"

mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
swap_total_kb=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
kv "mem_total_mb"   "$((mem_total_kb / 1024))"
kv "swap_total_mb"  "$((swap_total_kb / 1024))"
kv "hugepages_total" "$(awk '/^HugePages_Total:/ {print $2}' /proc/meminfo)"
kv "swappiness"     "$(cat /proc/sys/vm/swappiness 2>/dev/null || echo n/a)"
kv "transparent_hugepage" "$(awk -F'[][]' '{print $2}' /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo n/a)"

if [[ -d /sys/module/zswap ]]; then
  kv "zswap_enabled"    "$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo n/a)"
  kv "zswap_compressor" "$(cat /sys/module/zswap/parameters/compressor 2>/dev/null || echo n/a)"
  kv "zswap_max_pool_percent" "$(cat /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || echo n/a)"
fi

# ---- 5. Storage --------------------------------------------------------------
section "5. Storage"
status "Storage"

if have lsblk; then
  run_capture "lsblk" lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,ROTA,RM
fi

# Mount table, but filter the noisy pseudo-fs entries that don't matter for diff.
run_capture "mounts_real" awk '
  $3 !~ /^(cgroup|cgroup2|debugfs|tracefs|securityfs|bpf|fusectl|mqueue|pstore|configfs|hugetlbfs|nsfs|autofs|fuse\..+|rpc_pipefs|devpts|sysfs|proc|tmpfs|ramfs|overlay|squashfs|binfmt_misc|efivarfs)$/ {
    print $1, $2, $3, $4
  }' /proc/mounts

# ---- 6. Network --------------------------------------------------------------
section "6. Network"
status "Network"

if have ip; then
  run_capture "ip_link" ip -br link
  run_capture "ip_addr" ip -br addr
  gw="$(ip route 2>/dev/null | awk '/^default/ {print $3; exit}')"
  [[ -n "${gw:-}" ]] && kv "default_gateway" "$gw"
fi

# Per-interface link speed / driver — useful when comparing two boxes.
if have ethtool; then
  for ifc in $(ip -br link 2>/dev/null | awk '$2=="UP" && $1!~/^(lo|docker|veth|br-|virbr)/ {print $1}'); do
    kv "ethtool_${ifc}_speed"  "$(ethtool "$ifc" 2>/dev/null | awk -F': ' '/Speed:/ {print $2; exit}')"
    kv "ethtool_${ifc}_driver" "$(ethtool -i "$ifc" 2>/dev/null | awk -F': ' '/^driver:/ {print $2; exit}')"
  done
fi

# ---- 7. Linux 7.0 feature probes --------------------------------------------
section "7. Linux 7.0 Feature Probes"
status "kernel feature probes"

# Kernel build options that mark 7.0-era functionality.
for opt in CONFIG_RUST CONFIG_RUSTC_VERSION_TEXT CONFIG_IO_URING CONFIG_BPF_LSM \
           CONFIG_MODULE_SIG_HASH CONFIG_XFS_ONLINE_SCRUB CONFIG_XFS_DRAIN_INTENTS \
           CONFIG_XFS_LIVE_HOOKS CONFIG_PREEMPT_DYNAMIC; do
  kv "$opt" "$(probe_config "$opt" || true)"
done

# AccECN: Linux 7.0 ships RFC 9768 sysctls and enables negotiation by default.
# Capturing 4 keys; missing ones imply pre-7.0 kernel.
for s in net.ipv4.tcp_ecn net.ipv4.tcp_ecn_fallback \
         net.ipv4.tcp_ecn_option net.ipv4.tcp_ecn_option_beacon; do
  v="$(sysctl -n "$s" 2>/dev/null || echo MISSING)"
  kv "sysctl_${s//./_}" "$v"
done

# io_uring exposure status — some hardened distros disable it via sysctl.
kv "io_uring_disabled" "$(sysctl -n kernel.io_uring_disabled 2>/dev/null || echo n/a)"

# Loaded Rust modules (proxy for: are stable Rust drivers actually being used).
if [[ -r /sys/module ]]; then
  rust_mods="$(find /sys/module -maxdepth 2 -name 'rust' -type d 2>/dev/null | wc -l)"
  kv "loaded_rust_modules" "$rust_mods"
fi

# ---- 8. Power & Frequency snapshot ------------------------------------------
section "8. Power & Frequency"
status "frequency snapshot"

freqs="$(for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
  [[ -r "$c" ]] && cat "$c"
done | sort -n)"
if [[ -n "$freqs" ]]; then
  kv "cpu_cur_freq_min_khz" "$(printf '%s' "$freqs" | head -1)"
  kv "cpu_cur_freq_max_khz" "$(printf '%s' "$freqs" | tail -1)"
  kv "cpu_cur_freq_avg_khz" "$(printf '%s' "$freqs" | awk '{s+=$1;n++} END{if(n>0) printf "%d", s/n}')"
fi

# Battery — present on laptops, helps confirm AC vs battery (perf differs).
for ac in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do
  [[ -r "$ac" ]] && { kv "ac_online" "$(<"$ac")"; break; }
done

# ---- 9. Benchmarks -----------------------------------------------------------
section "9. Benchmarks"
status "Benchmarks"

# 9a. CPU: openssl is universally available and produces reproducible numbers.
if have openssl; then
  status "openssl AES-256-GCM single (${CPU_SECONDS}s)"
  out="$(openssl speed -evp aes-256-gcm -seconds "$CPU_SECONDS" -bytes 16384 2>&1 | tail -3 || true)"
  report "### bench_cpu_aes256gcm_single"; report '```'; printf '%s\n' "$out" >> "$OUT_FILE"; report '```'

  status "openssl SHA-256 single (${CPU_SECONDS}s)"
  out="$(openssl speed -evp sha256 -seconds "$CPU_SECONDS" -bytes 16384 2>&1 | tail -3 || true)"
  report "### bench_cpu_sha256_single"; report '```'; printf '%s\n' "$out" >> "$OUT_FILE"; report '```'

  if [[ "$(nproc)" -gt 1 ]]; then
    status "openssl AES-256-GCM multi -multi $(nproc) (${CPU_SECONDS}s)"
    out="$(openssl speed -evp aes-256-gcm -multi "$(nproc)" -seconds "$CPU_SECONDS" -bytes 16384 2>&1 | tail -5 || true)"
    report "### bench_cpu_aes256gcm_multi"; report '```'; printf '%s\n' "$out" >> "$OUT_FILE"; report '```'
  fi
else
  kv "bench_cpu" "SKIPPED (openssl missing)"
fi

# 9b. Memory bandwidth — dd from /dev/zero to /dev/null is a rough but
# universal proxy for memcpy throughput. Real tool (sysbench memory) preferred.
status "memory bandwidth (dd ${MEM_GB} GB zero->null)"
out="$(dd if=/dev/zero of=/dev/null bs=1M count=$((MEM_GB * 1024)) 2>&1 || true)"
report "### bench_mem_bandwidth_dd"; report '```'; printf '%s\n' "$out" >> "$OUT_FILE"; report '```'

# 9c. Disk: write with O_DIRECT (bypasses page cache) and fsync; read with
# O_DIRECT to avoid measuring the cache we just populated. Some filesystems
# (notably tmpfs, some btrfs configs) reject O_DIRECT — fall back accordingly.
BENCH_DIR="$(pick_bench_dir)"
if [[ -n "$BENCH_DIR" ]]; then
  BENCH_FILE="${BENCH_DIR%/}/.baseline_bench.dat"
  bench_fst="$(findmnt -no FSTYPE,SOURCE --target "$BENCH_DIR" 2>/dev/null || echo unknown)"
  kv "bench_disk_dir" "$BENCH_DIR"
  kv "bench_disk_fs"  "$bench_fst"

  status "disk write ${DD_MB}MB direct+fsync"
  if w="$(dd if=/dev/zero of="$BENCH_FILE" bs=1M count="$DD_MB" oflag=direct conv=fsync 2>&1)"; then
    report "### bench_disk_write_direct"
  else
    status "  direct write rejected — falling back to fdatasync"
    w="$(dd if=/dev/zero of="$BENCH_FILE" bs=1M count="$DD_MB" conv=fdatasync 2>&1 || true)"
    report "### bench_disk_write_fdatasync"
  fi
  report '```'; printf '%s\n' "$w" >> "$OUT_FILE"; report '```'

  status "disk read ${DD_MB}MB direct"
  if r="$(dd if="$BENCH_FILE" of=/dev/null bs=1M iflag=direct 2>&1)"; then
    report "### bench_disk_read_direct"
  else
    status "  direct read rejected — falling back to cached read"
    r="$(dd if="$BENCH_FILE" of=/dev/null bs=1M 2>&1 || true)"
    report "### bench_disk_read_cached"
  fi
  report '```'; printf '%s\n' "$r" >> "$OUT_FILE"; report '```'
else
  kv "bench_disk" "SKIPPED (no non-tmpfs writable dir found)"
fi

# 9d. Optional richer benches — only run if the tools are already installed.
if have sysbench; then
  status "sysbench cpu (10s, $(nproc) threads)"
  out="$(sysbench cpu --time=10 --threads="$(nproc)" run 2>&1 | tail -20 || true)"
  report "### bench_sysbench_cpu"; report '```'; printf '%s\n' "$out" >> "$OUT_FILE"; report '```'

  status "sysbench memory (10s)"
  out="$(sysbench memory --time=10 --threads="$(nproc)" run 2>&1 | tail -20 || true)"
  report "### bench_sysbench_memory"; report '```'; printf '%s\n' "$out" >> "$OUT_FILE"; report '```'
fi
if have fio && [[ -n "$BENCH_DIR" ]]; then
  status "fio randread 4k iodepth=32 (10s)"
  fio_file="$BENCH_DIR/.fio_bench"
  out="$(fio --name=baseline --filename="$fio_file" --size="${DD_MB}M" --bs=4k \
    --rw=randread --ioengine=libaio --iodepth=32 --direct=1 \
    --time_based --runtime=10 --group_reporting 2>&1 | tail -25 || true)"
  report "### bench_fio_randread_4k"; report '```'; printf '%s\n' "$out" >> "$OUT_FILE"; report '```'
  rm -f "$fio_file"
fi

# Guardian Shield's libwarden.so LD_PRELOAD prints a 2-line banner on stderr
# of every spawned binary; those lines get captured by `2>&1` and pollute the
# report (and any diff against a machine without warden). Strip them here in
# one pass rather than wrapping every capture site.
sed -i -E '/^\[libwarden\.so\]/d' "$OUT_FILE"

# ---- 10. Run info ------------------------------------------------------------
END_EPOCH=$(date +%s)
section "10. Run Info"
kv "duration_seconds" "$((END_EPOCH - START_EPOCH))"
kv "tools_present"    "$(for t in openssl dd lscpu lsblk ip ethtool sysbench fio stress-ng cyclictest hdparm bpftrace; do have "$t" && printf '%s ' "$t"; done)"
kv "running_as"       "$(id -un)"
kv "is_root"          "$([[ $EUID -eq 0 ]] && echo yes || echo no)"

status ""
status "Wrote: $OUT_FILE"
status ""
status "Compare two reports:  diff -u baseline-A.txt baseline-B.txt | less"
printf '%s\n' "$OUT_FILE"
