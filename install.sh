#!/bin/bash
# ============================================================================
#
#        ██╗███████╗███████╗████████╗███████╗██████╗ ███╗   ██╗███████╗████████╗
#        ██║██╔════╝██╔════╝╚══██╔══╝██╔════╝██╔══██╗████╗  ██║██╔════╝╚══██╔══╝
#        ██║█████╗  ███████╗   ██║   █████╗  ██████╔╝██╔██╗ ██║█████╗     ██║
#   ██   ██║██╔══╝  ╚════██║   ██║   ██╔══╝  ██╔══██╗██║╚██╗██║██╔══╝     ██║
#   ╚█████╔╝███████╗███████║   ██║   ███████╗██║  ██║██║ ╚████║███████╗   ██║
#    ╚════╝ ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝
#
#                    ARCH LINUX INSTALLATION SCRIPT
#                      Quantum Field Medic Edition
#
# ============================================================================
# Deploy from: Ventoy USB | Android ADB | Any Live Environment
# ============================================================================

# Resilience: NO `set -e`. We track failures explicitly and soldier on through
# non-critical errors. Fatal failures (partition, pacstrap, bootloader) call
# `die` to abort. Everything else uses `try_step` to log + continue.
#
# This is the "fighter-jet" install: a hiccup in nvidia or theme install must
# not crash the partitioning or leave a half-installed system. The user should
# always reach a bootable Arch with a summary of what to fix manually.
set -u  # error on unset vars, but not on command failures
set -o pipefail  # bubble pipe failures up to $? so try_step sees them

# Ensure TERM is set (required for SSH/ADB deployments)
export TERM="${TERM:-xterm}"

# ----------------------------------------------------------------------------
# Default-init every variable that may be set by an optional config file.
# Without these, set -u trips the moment any code-path checks `[ -n "$VAR" ]`
# while running interactively (no config file sourced). Use := so an existing
# value (e.g. exported in the env) wins; otherwise the var becomes "".
# ----------------------------------------------------------------------------
: "${CONFIG_FILE:=}"            # path to sourced config file, if any
: "${TARGET_DISK:=}"            # /dev/nvmeXn1 or /dev/sdX from config
: "${USER_PASSWORD:=}"          # if set, skip interactive prompt
: "${DESKTOP_STYLE:=}"          # dock | windows
: "${DEV_STACKS:=}"             # space-separated list, e.g. "tauri go python"
: "${MIRROR_COUNTRY:=}"         # reflector --country argument
: "${STATIC_IP:=}"              # CIDR static IP for enterprise config
: "${GATEWAY:=}"                # gateway IP, paired with STATIC_IP
: "${HTTP_PROXY:=}"             # proxy URL for /etc/environment
: "${SSH_AUTHORIZED_KEYS:=}"    # path to authorized_keys to seed
: "${DOMAIN_REALM:=}"           # AD/realm join string
: "${POST_INSTALL_HOOK:=}"      # extra script to run at the end

# Failure ledger — populated by try_step / try_func, printed at end.
FAILED_STEPS=()
SKIPPED_STEPS=()
INSTALL_LOG="/var/log/jesternet-install.log"

# ============================================================================
# Configuration - EDIT THESE FOR YOUR SETUP
# ============================================================================

# Default values (will be overridden by interactive prompts or config file)
HOSTNAME="jesternet"
USERNAME="architect"
TIMEZONE="America/New_York"
LOCALE="en_US.UTF-8"
KEYMAP="us"

# Partition sizes (in GB) - Set to "auto" for smart sizing based on disk
# These can be overridden in enterprise config files
EFI_SIZE="1"          # 1GB EFI partition (fixed, standard)
SWAP_SIZE="auto"      # Auto-calculated based on disk size (4-32GB)
ROOT_SIZE="auto"      # Auto-calculated based on disk size (30-300GB)
# HOME gets the rest of the disk

# Desktop style: "dock" (macOS) or "taskbar" (Windows)
DESKTOP_STYLE="dock"

# Development stacks to install (space-separated)
# Options: tauri go python zig web android office creator
DEV_STACKS=""

# ============================================================================
# Enterprise Configuration (for mass deployments)
# ============================================================================

# Mirror country (ISO 3166-1 alpha-2 code, e.g., US, DE, GB, AU)
MIRROR_COUNTRY="US"

# Network configuration (leave empty for DHCP)
STATIC_IP=""              # e.g., "192.168.1.100/24"
GATEWAY=""                # e.g., "192.168.1.1"
DNS_SERVERS=""            # e.g., "8.8.8.8,8.8.4.4"

# Proxy configuration (leave empty for no proxy)
HTTP_PROXY=""             # e.g., "http://proxy.corp.com:8080"
HTTPS_PROXY=""

# SSH configuration
SSH_ENABLED="true"        # Enable SSH server
SSH_AUTHORIZED_KEYS=""    # Path to authorized_keys file to inject

# Post-install hook script (runs at end of installation)
POST_INSTALL_HOOK=""      # Path to custom script to run

# Fleet management / domain join preparation
DOMAIN_JOIN_PREP="false"  # Install packages for AD/LDAP join
DOMAIN_REALM=""           # e.g., "CORP.EXAMPLE.COM"

# ============================================================================
# Colors
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================================
# Logging
# ============================================================================

_log_to_file() {
    # Write a plain copy (no colour codes) to the install log if it exists.
    [ -n "${INSTALL_LOG:-}" ] && [ -w "$(dirname "$INSTALL_LOG")" ] && \
        printf '[%s] %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$1" >> "$INSTALL_LOG" 2>/dev/null || true
}

log_step() {
    echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"
    _log_to_file "STEP    $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
    _log_to_file "OK      $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    _log_to_file "WARN    $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    _log_to_file "ERROR   $1"
}

# ============================================================================
# Resilience helpers — "fighter-jet" mode
# ============================================================================

# Init the persistent install log. Called once early in main().
init_install_log() {
    # Prefer /var/log (always writable as root in live ISO), fallback to /tmp.
    local d
    d="$(dirname "$INSTALL_LOG")"
    mkdir -p "$d" 2>/dev/null
    if ! ( : > "$INSTALL_LOG" ) 2>/dev/null; then
        INSTALL_LOG="/tmp/jesternet-install.log"
        : > "$INSTALL_LOG" 2>/dev/null || INSTALL_LOG=""
    fi
    if [ -n "$INSTALL_LOG" ]; then
        log_step "install log: $INSTALL_LOG"
    fi
}

# Fatal: stop the install. Use only when continuing would corrupt the system
# (failed partitioning, pacstrap, or bootloader install).
die() {
    log_error "FATAL: $*"
    log_error "Cannot continue. Log: ${INSTALL_LOG:-<no log>}"
    print_failure_summary
    exit 1
}

# ---------------------------------------------------------------------------
# Visible exit — runs on ANY non-zero exit (die, set -u trip, SIGINT, broken
# pipe, etc.) so the user is never left guessing what happened. Without this,
# a die on a noisy pacstrap failure scrolls off-screen and the user just sees
# their live ISO prompt come back.
# ---------------------------------------------------------------------------
_on_exit() {
    local rc=$?
    trap - EXIT      # don't recurse if anything below errors
    [[ $rc -eq 0 ]] && return 0

    printf '\n%b\n' "${RED:-}═══════════════════════════════════════════════════════════════${NC:-}"
    printf '%b\n'   "${RED:-}  ✗ JESTERNET INSTALL ABORTED  (exit ${rc})${NC:-}"
    printf '%b\n'   "${RED:-}═══════════════════════════════════════════════════════════════${NC:-}"

    if [[ -n "${INSTALL_LOG:-}" && -f "${INSTALL_LOG}" ]]; then
        printf '\n%b\n' "${YELLOW:-}Last 40 lines of ${INSTALL_LOG}:${NC:-}"
        tail -n 40 "$INSTALL_LOG" 2>/dev/null
    else
        printf '\n%b\n' "${YELLOW:-}(no install log was created)${NC:-}"
    fi

    printf '\n%b\n' "${YELLOW:-}To investigate:${NC:-}"
    printf '  less %s\n' "${INSTALL_LOG:-/var/log/jesternet-install.log}"
    printf '  lsblk                            # see partitions / mount state\n'
    printf '  mount | grep /mnt                # see anything stuck mounted\n'
    printf '  bash %s    # retry — prepare_clean_state recovers prior state\n' "${0:-install.sh}"

    printf '\n%b' "${YELLOW:-}Press Enter to drop to the live ISO shell...${NC:-}"
    read -r < /dev/tty 2>/dev/null || true
    exit "$rc"
}
trap _on_exit EXIT

# Run a named function, tolerating its failures. Used for the install phases
# that are nice-to-have (theme, dev-stacks, AUR helper, enterprise config).
try_func() {
    local desc="$1"
    local fn="$2"
    log_step ">>> $desc"
    if ( "$fn" ); then
        log_success "$desc"
        return 0
    fi
    local rc=$?
    log_error "$desc failed (rc=$rc) — continuing"
    FAILED_STEPS+=("$desc (rc=$rc)")
    return $rc
}

# Run a single command tolerantly. Returns the command's rc but logs a
# failure into FAILED_STEPS without aborting.
# Usage: try_cmd "human description" -- pacman -S --noconfirm foo bar
try_cmd() {
    local desc="$1"
    shift
    [ "${1:-}" = "--" ] && shift
    log_step "$desc"
    if "$@"; then
        log_success "$desc"
        return 0
    fi
    local rc=$?
    log_error "$desc — exit $rc (continuing)"
    FAILED_STEPS+=("$desc (rc=$rc)")
    return $rc
}

print_failure_summary() {
    if [ "${#FAILED_STEPS[@]}" -eq 0 ] && [ "${#SKIPPED_STEPS[@]}" -eq 0 ]; then
        return
    fi
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}            STEPS THAT NEED MANUAL ATTENTION${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    if [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
        echo -e "${RED}Failed:${NC}"
        for s in "${FAILED_STEPS[@]}"; do
            echo "  ✗ $s"
        done
    fi
    if [ "${#SKIPPED_STEPS[@]}" -gt 0 ]; then
        echo -e "${YELLOW}Skipped:${NC}"
        for s in "${SKIPPED_STEPS[@]}"; do
            echo "  · $s"
        done
    fi
    echo ""
    echo -e "${CYAN}Full log: ${INSTALL_LOG:-<none>}${NC}"
    echo -e "${CYAN}Most issues can be fixed after first boot with:${NC}"
    echo "  sudo pacman -Syu                 # bring everything in sync"
    echo "  sudo pacman -S --needed <pkg>    # retry a missing package"
    echo "  cd ~/JesterNet && bash install-dev-stacks.sh    # retry dev stacks"
    echo ""
}

# ============================================================================
# Smart Partition Sizing
# ============================================================================

calculate_partition_sizes() {
    local disk_gb=$1

    log_step "Calculating optimal partition sizes for ${disk_gb}GB disk..."

    # EFI is always 1GB
    EFI_SIZE=1

    # Swap sizing (if set to "auto")
    # Scale: 4GB for small disks, up to 32GB for very large disks
    if [ "$SWAP_SIZE" = "auto" ]; then
        if [ "$disk_gb" -lt 64 ]; then
            SWAP_SIZE=2
        elif [ "$disk_gb" -lt 128 ]; then
            SWAP_SIZE=4
        elif [ "$disk_gb" -lt 256 ]; then
            SWAP_SIZE=8
        elif [ "$disk_gb" -lt 512 ]; then
            SWAP_SIZE=8
        elif [ "$disk_gb" -lt 1024 ]; then
            SWAP_SIZE=16
        elif [ "$disk_gb" -lt 2048 ]; then
            SWAP_SIZE=16
        else
            SWAP_SIZE=32
        fi
    fi

    # Root sizing (if set to "auto")
    # Scale based on disk size with sensible minimums and maximums
    # Minimum 30GB, maximum 300GB
    if [ "$ROOT_SIZE" = "auto" ]; then
        if [ "$disk_gb" -lt 64 ]; then
            # Tiny disk: minimal root
            ROOT_SIZE=25
        elif [ "$disk_gb" -lt 128 ]; then
            # Small disk (64-128GB): ~30GB root
            ROOT_SIZE=30
        elif [ "$disk_gb" -lt 256 ]; then
            # Medium-small (128-256GB): ~50GB root
            ROOT_SIZE=50
        elif [ "$disk_gb" -lt 512 ]; then
            # Medium (256-512GB): ~80GB root
            ROOT_SIZE=80
        elif [ "$disk_gb" -lt 1024 ]; then
            # Large (512GB-1TB): ~150GB root
            ROOT_SIZE=150
        elif [ "$disk_gb" -lt 2048 ]; then
            # Very large (1-2TB): ~200GB root
            ROOT_SIZE=200
        elif [ "$disk_gb" -lt 4096 ]; then
            # Huge (2-4TB): ~250GB root
            ROOT_SIZE=250
        else
            # Massive (4TB+): ~300GB root (cap)
            ROOT_SIZE=300
        fi
    fi

    log_success "Partition sizing: EFI=${EFI_SIZE}GB, Swap=${SWAP_SIZE}GB, Root=${ROOT_SIZE}GB"
}

# ============================================================================
# Banner
# ============================================================================

print_banner() {
    clear
    echo -e "${MAGENTA}"
    cat << 'EOF'

     ██╗███████╗███████╗████████╗███████╗██████╗ ███╗   ██╗███████╗████████╗
     ██║██╔════╝██╔════╝╚══██╔══╝██╔════╝██╔══██╗████╗  ██║██╔════╝╚══██╔══╝
     ██║█████╗  ███████╗   ██║   █████╗  ██████╔╝██╔██╗ ██║█████╗     ██║
██   ██║██╔══╝  ╚════██║   ██║   ██╔══╝  ██╔══██╗██║╚██╗██║██╔══╝     ██║
╚█████╔╝███████╗███████║   ██║   ███████╗██║  ██║██║ ╚████║███████╗   ██║
 ╚════╝ ╚══════╝╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝

                 ╔═══════════════════════════════════════╗
                 ║   ARCH LINUX INSTALLATION SCRIPT      ║
                 ║     Quantum Field Medic Edition       ║
                 ╚═══════════════════════════════════════╝

EOF
    echo -e "${NC}"
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

preflight_checks() {
    log_step "Running pre-flight checks..."

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Run: sudo $0"
        exit 1
    fi

    # Check if booted in UEFI mode
    if [ ! -d /sys/firmware/efi ]; then
        log_error "System not booted in UEFI mode"
        echo "Please boot in UEFI mode to continue"
        exit 1
    fi
    log_success "UEFI mode detected"

    # Check internet connectivity (use IP to avoid DNS issues)
    if ! ping -c 1 -W 5 8.8.8.8 &> /dev/null; then
        log_error "No internet connection"
        echo "Please connect to the internet first"
        echo "  For WiFi: iwctl station wlan0 connect <SSID>"
        exit 1
    fi
    log_success "Internet connection active"

    # Ensure DNS is working (use Cloudflare as fallback)
    if ! getent hosts archlinux.org &> /dev/null; then
        log_warning "DNS not configured, setting up fallback..."
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    fi

    # Check if arch-chroot is available
    if ! command -v arch-chroot &> /dev/null; then
        log_error "arch-chroot not found. Are you in the Arch live environment?"
        exit 1
    fi
    log_success "Arch live environment detected"

    # Verify the toolchain we'll need for partitioning + recovery is present.
    # Arch live ISO ships all of these — if any are missing, we're not where
    # we think we are.
    local missing=()
    for tool in parted wipefs partprobe pacstrap genfstab udevadm mountpoint swapon swapoff; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        log_error "Missing required tools in live environment: ${missing[*]}"
        log_error "This usually means we're not running on an Arch live ISO."
        exit 1
    fi
    log_success "Required tools present"

    # Sync time
    log_step "Syncing system clock..."
    timedatectl set-ntp true 2>/dev/null || log_warning "NTP sync failed (non-fatal)"
    log_success "System clock synced"

    # Update pacman keyring (critical for older ISOs)
    log_step "Updating pacman keyring (required for older installation media)..."
    pacman-key --init 2>/dev/null || true
    pacman-key --populate archlinux 2>/dev/null || true
    pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true
    log_success "Keyring updated"
}

# ============================================================================
# Disk Selection
# ============================================================================

list_disks() {
    echo ""
    echo -e "${CYAN}Available disks:${NC}"
    echo ""
    lsblk -d -p -n -o NAME,SIZE,TYPE,MODEL | awk '$3 == "disk"' | grep -vE "^/dev/(loop|sr|fd|ram)" | while read line; do
        echo "  $line"
    done
    echo ""
}

select_disk() {
    list_disks

    echo -e "${YELLOW}WARNING: The selected disk will be COMPLETELY ERASED!${NC}"
    echo ""

    # If TARGET_DISK already set from config, use it
    if [ -n "$TARGET_DISK" ] && [ -b "$TARGET_DISK" ]; then
        log_step "Using disk from config: $TARGET_DISK"
    else
        read -p "Enter disk to install to (e.g., /dev/nvme0n1 or /dev/sda): " TARGET_DISK
    fi

    # Validate disk exists
    if [ ! -b "$TARGET_DISK" ]; then
        log_error "Disk $TARGET_DISK does not exist"
        exit 1
    fi

    # Get disk size in GB
    DISK_SIZE_BYTES=$(lsblk -b -d -n -o SIZE "$TARGET_DISK")
    DISK_SIZE_GB=$((DISK_SIZE_BYTES / 1024 / 1024 / 1024))

    echo ""
    echo -e "Selected disk: ${GREEN}$TARGET_DISK${NC} (${DISK_SIZE_GB}GB)"
    echo ""

    # Calculate optimal partition sizes based on disk size
    calculate_partition_sizes "$DISK_SIZE_GB"

    # Calculate home size (gets remaining space)
    HOME_SIZE=$((DISK_SIZE_GB - EFI_SIZE - SWAP_SIZE - ROOT_SIZE - 1))

    if [ "$HOME_SIZE" -lt 5 ]; then
        log_error "Disk too small. Need at least $((EFI_SIZE + SWAP_SIZE + ROOT_SIZE + 5))GB (minimum ~40GB recommended)"
        exit 1
    fi

    echo "Partition layout:"
    echo "  EFI:  ${EFI_SIZE}GB"
    echo "  SWAP: ${SWAP_SIZE}GB"
    echo "  ROOT: ${ROOT_SIZE}GB  (/)"
    echo "  HOME: ${HOME_SIZE}GB  (/home)"
    echo ""

    # If config file provided, auto-confirm
    if [ -n "$CONFIG_FILE" ]; then
        log_step "Auto-confirming from config file..."
    else
        read -p "Proceed with installation? This will ERASE ALL DATA on $TARGET_DISK [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled"
            exit 0
        fi
    fi
}

# ============================================================================
# User Configuration
# ============================================================================

configure_user() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                    USER CONFIGURATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # If using config file, skip interactive prompts (but require password)
    if [ -n "$CONFIG_FILE" ]; then
        log_step "Using configuration from $CONFIG_FILE"
        echo "  Hostname: $HOSTNAME"
        echo "  Username: $USERNAME"
        echo "  Timezone: $TIMEZONE"

        # Password must still be set - prompt if missing from config
        if [ -z "$USER_PASSWORD" ]; then
            while true; do
                read -s -p "Password: " USER_PASSWORD
                echo ""
                read -s -p "Confirm password: " USER_PASSWORD_CONFIRM
                echo ""
                if [ "$USER_PASSWORD" = "$USER_PASSWORD_CONFIRM" ]; then
                    break
                else
                    log_error "Passwords do not match. Try again."
                fi
            done
        fi

        log_success "Configuration loaded from file"
        return
    fi

    read -p "Hostname [$HOSTNAME]: " input
    HOSTNAME="${input:-$HOSTNAME}"

    read -p "Username [$USERNAME]: " input
    USERNAME="${input:-$USERNAME}"

    while true; do
        read -s -p "Password: " USER_PASSWORD
        echo ""
        read -s -p "Confirm password: " USER_PASSWORD_CONFIRM
        echo ""

        if [ "$USER_PASSWORD" = "$USER_PASSWORD_CONFIRM" ]; then
            break
        else
            log_error "Passwords do not match. Try again."
        fi
    done

    # Timezone selection
    echo ""
    echo "Common timezones:"
    echo "  1) America/New_York"
    echo "  2) America/Los_Angeles"
    echo "  3) America/Chicago"
    echo "  4) Europe/London"
    echo "  5) Europe/Berlin"
    echo "  6) Asia/Tokyo"
    echo "  7) Australia/Sydney"
    echo "  8) Other (manual entry)"
    echo ""
    read -p "Select timezone [1]: " tz_choice

    case "${tz_choice:-1}" in
        1) TIMEZONE="America/New_York" ;;
        2) TIMEZONE="America/Los_Angeles" ;;
        3) TIMEZONE="America/Chicago" ;;
        4) TIMEZONE="Europe/London" ;;
        5) TIMEZONE="Europe/Berlin" ;;
        6) TIMEZONE="Asia/Tokyo" ;;
        7) TIMEZONE="Australia/Sydney" ;;
        8) read -p "Enter timezone: " TIMEZONE ;;
    esac

    log_success "Configuration complete"
}

# ============================================================================
# Desktop Style Selection
# ============================================================================

select_desktop_style() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                    DESKTOP STYLE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # If using config file with DESKTOP_STYLE set, skip prompt
    if [ -n "$CONFIG_FILE" ] && [ -n "$DESKTOP_STYLE" ]; then
        log_step "Using desktop style from config: $DESKTOP_STYLE"
        return
    fi

    echo -e "  ${GREEN}[D]${NC} Dock Bar ${CYAN}(macOS-style)${NC}"
    echo "      Bottom dock, auto-hide, clean top bar"
    echo ""
    echo -e "  ${BLUE}[W]${NC} Windows Bar ${CYAN}(Taskbar-style)${NC}"
    echo "      Full taskbar, app menu, system tray"
    echo ""

    read -p "Select style [D/W]: " style_choice

    case "${style_choice^^}" in
        W|WINDOWS) DESKTOP_STYLE="taskbar" ;;
        *) DESKTOP_STYLE="dock" ;;
    esac

    log_success "Desktop style: $DESKTOP_STYLE"
}

# ============================================================================
# Development Stacks Selection
# ============================================================================

select_dev_stacks() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}              DEVELOPMENT STACKS (Optional)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # If using config file, skip prompt and use DEV_STACKS from config
    if [ -n "$CONFIG_FILE" ]; then
        if [ -n "$DEV_STACKS" ]; then
            log_step "Using dev stacks from config: $DEV_STACKS"
        else
            log_step "No dev stacks selected in config"
        fi
        return
    fi

    echo "Select development environments to install (space-separated numbers):"
    echo ""
    echo "  1) Tauri      - Rust + Svelte/React desktop apps"
    echo "  2) Android    - SDK + NDK + Kotlin + Gradle"
    echo "  3) Go         - Go + tools + LSP"
    echo "  4) Python     - Poetry + Ruff + Pyright"
    echo "  5) Zig        - Zig + ZLS"
    echo "  6) Web        - Node + Bun + Vite + Tailwind"
    echo "  7) Office     - LibreOffice + GIMP + VLC"
    echo "  8) Creator    - OBS + Kdenlive + Audacity"
    echo "  9) ALL        - Install everything"
    echo "  0) NONE       - Skip (can install later)"
    echo ""

    read -p "Enter choices (e.g., '1 3 6' or '9' for all) [0]: " stack_choices

    DEV_STACKS=""
    for choice in $stack_choices; do
        case "$choice" in
            1) DEV_STACKS="$DEV_STACKS tauri" ;;
            2) DEV_STACKS="$DEV_STACKS android" ;;
            3) DEV_STACKS="$DEV_STACKS go" ;;
            4) DEV_STACKS="$DEV_STACKS python" ;;
            5) DEV_STACKS="$DEV_STACKS zig" ;;
            6) DEV_STACKS="$DEV_STACKS web" ;;
            7) DEV_STACKS="$DEV_STACKS office" ;;
            8) DEV_STACKS="$DEV_STACKS creator" ;;
            9) DEV_STACKS="tauri android go python zig web office creator" ;;
            0|"") DEV_STACKS="" ;;
        esac
    done

    if [ -n "$DEV_STACKS" ]; then
        log_success "Selected stacks:$DEV_STACKS"
    else
        log_success "No development stacks selected"
    fi
}

# ============================================================================
# Recovery: clean state from any prior failed install
# ============================================================================

prepare_clean_state() {
    # Idempotent reset of /mnt, swap, dm-crypt, and zombie chroot processes.
    # Safe to call on a fresh boot (everything is already clean — silent no-ops).
    # Without this, a re-run after a crashed install hits "device busy" on
    # umount, "swap already in use" on swapon, or stale mounts under /mnt that
    # leak the new install's data into the ISO's tmpfs.
    log_step "Preparing clean state (recovering from any prior install attempt)..."

    # Step out of /mnt if we somehow ended up there — protects us from the
    # fuser sweep below (otherwise we'd kill ourselves).
    cd / 2>/dev/null || true

    # 1. Kill any process holding files in /mnt — usually leftover bash from
    #    a half-run chroot that was Ctrl-C'd. Critically, exclude this script
    #    AND its parent shell from the kill list. fuser -km is otherwise
    #    indiscriminate: on re-runs it'll happily SIGKILL the live install.sh
    #    if anything in the process tree has fds open under /mnt, with no
    #    error message — the user just sees a black flash and lands back at
    #    the live ISO shell. That's the failure mode this guard prevents.
    if command -v fuser &>/dev/null && mountpoint -q /mnt 2>/dev/null; then
        local me=$$ parent=$PPID
        local victims
        # fuser -m prints PIDs space-separated on stderr; flatten and filter.
        victims="$(fuser -m /mnt 2>&1 | tr -cd '0-9 \n' | tr ' \n' '\n\n' \
            | awk -v me="$me" -v p="$parent" 'NF && $1!=me && $1!=p' \
            | sort -u)"
        if [ -n "$victims" ]; then
            log_step "Killing leftover /mnt processes: $(echo $victims | tr '\n' ' ')"
            # shellcheck disable=SC2086
            kill -9 $victims 2>/dev/null || true
            sleep 1
        fi
    fi

    # 2. Recursively unmount /mnt. -R handles nested mounts (boot/efi, etc.),
    #    -l (lazy) covers the case where something's still holding it.
    if mountpoint -q /mnt 2>/dev/null; then
        log_step "Found existing mount under /mnt — unmounting"
        umount -R /mnt 2>/dev/null || umount -lR /mnt 2>/dev/null || true
    fi

    # 3. Disable any active swap. If we partitioned the target disk last
    #    attempt and swapon'd it, parted will fail this time without this.
    if [ -n "$(swapon --show=NAME --noheadings 2>/dev/null)" ]; then
        log_step "Active swap detected — disabling"
        swapoff -a 2>/dev/null || true
    fi

    # 4. Close any LUKS volumes that might be lingering from a prior crypto
    #    setup attempt (defensive — we don't open any in this script today,
    #    but future versions might, and dm leftovers block wipefs).
    if command -v cryptsetup &>/dev/null && command -v dmsetup &>/dev/null; then
        for dm in $(dmsetup ls --target crypt 2>/dev/null | awk '{print $1}'); do
            [ -z "$dm" ] || [ "$dm" = "No" ] && continue
            log_step "Closing crypto volume: $dm"
            cryptsetup close "$dm" 2>/dev/null || true
        done
    fi

    # 5. Tell the kernel to drop any cached partition tables on the target
    #    disk. Without this, parted complains that the device is in use.
    if [ -n "${TARGET_DISK:-}" ] && [ -b "$TARGET_DISK" ]; then
        partprobe "$TARGET_DISK" 2>/dev/null || true
        udevadm settle 2>/dev/null || true
    fi

    log_success "Clean state ready"
}

# ============================================================================
# Partitioning
# ============================================================================

partition_disk() {
    log_step "Partitioning disk $TARGET_DISK..."

    # Determine partition naming: devices ending in a digit need 'p' separator
    # e.g. nvme0n1 -> nvme0n1p1, mmcblk0 -> mmcblk0p1, but sda -> sda1
    if [[ "$TARGET_DISK" =~ [0-9]$ ]]; then
        PART_PREFIX="${TARGET_DISK}p"
    else
        PART_PREFIX="${TARGET_DISK}"
    fi

    # Wipe existing partitions. This is the second line of defence after
    # prepare_clean_state — if any signature lingers (LVM, RAID, old GPT),
    # wipefs scrubs it so parted starts on a clean disk.
    wipefs -a "$TARGET_DISK" 2>/dev/null || true
    # Also zap the partition table itself in case wipefs missed something.
    if command -v sgdisk &>/dev/null; then
        sgdisk --zap-all "$TARGET_DISK" 2>/dev/null || true
    fi

    # Create GPT partition table
    parted -s "$TARGET_DISK" mklabel gpt

    # Calculate partition boundaries
    local efi_end=$((EFI_SIZE * 1024))
    local swap_end=$((efi_end + SWAP_SIZE * 1024))
    local root_end=$((swap_end + ROOT_SIZE * 1024))

    # Create partitions
    parted -s "$TARGET_DISK" mkpart "EFI" fat32 1MiB ${efi_end}MiB
    parted -s "$TARGET_DISK" set 1 esp on
    parted -s "$TARGET_DISK" mkpart "SWAP" linux-swap ${efi_end}MiB ${swap_end}MiB
    parted -s "$TARGET_DISK" mkpart "ROOT" ext4 ${swap_end}MiB ${root_end}MiB
    parted -s "$TARGET_DISK" mkpart "HOME" ext4 ${root_end}MiB 100%

    # Wait for kernel to recognize partitions
    sleep 2
    partprobe "$TARGET_DISK"
    sleep 2

    # Set partition variables
    EFI_PART="${PART_PREFIX}1"
    SWAP_PART="${PART_PREFIX}2"
    ROOT_PART="${PART_PREFIX}3"
    HOME_PART="${PART_PREFIX}4"

    log_success "Partitions created"

    # Format partitions
    log_step "Formatting partitions..."

    mkfs.fat -F32 "$EFI_PART"
    log_success "EFI partition formatted (FAT32)"

    mkswap "$SWAP_PART"
    log_success "Swap partition formatted"

    mkfs.ext4 -F "$ROOT_PART"
    log_success "Root partition formatted (ext4)"

    mkfs.ext4 -F "$HOME_PART"
    log_success "Home partition formatted (ext4)"

    # Mount partitions
    log_step "Mounting partitions..."

    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot/efi
    mkdir -p /mnt/home
    mount "$EFI_PART" /mnt/boot/efi
    mount "$HOME_PART" /mnt/home
    swapon "$SWAP_PART"

    log_success "Partitions mounted"
}

# ============================================================================
# Base System Installation
# ============================================================================

install_base_system() {
    log_step "Installing base system (this may take a while)..."

    # Tune the LIVE ISO's pacman.conf for parallel downloads + aria2 retries.
    # This speeds up pacstrap and gives us aria2's resilient retry behaviour
    # for free on the very first download cycle.
    log_step "Tuning live-ISO pacman.conf for parallel/aria2 downloads..."
    if ! grep -q '^ParallelDownloads' /etc/pacman.conf; then
        sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 8/' /etc/pacman.conf
        grep -q '^ParallelDownloads' /etc/pacman.conf || \
            echo 'ParallelDownloads = 8' >> /etc/pacman.conf
    fi
    # aria2 may not be installed on the ISO itself; only set XferCommand if present.
    if command -v aria2c &>/dev/null && ! grep -q '^XferCommand' /etc/pacman.conf; then
        sed -i '/^\[options\]/a XferCommand = /usr/bin/aria2c --allow-overwrite=true --continue=true --file-allocation=none --log-level=error --max-tries=4 --max-connection-per-server=8 --max-file-not-found=4 --min-split-size=5M --no-conf --remote-time=true --summary-interval=60 --timeout=10 --retry-wait=1 --console-log-level=error --download-result=hide --quiet -d / -o %o %u' /etc/pacman.conf
    fi
    log_success "Pacman tuned"

    # Update mirrorlist for faster downloads
    log_step "Optimizing mirror list..."

    # Always prepend the official geo-load-balanced mirror (fastest, most reliable)
    local geo_mirror="Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch"

    if [ -n "$MIRROR_COUNTRY" ] && command -v reflector &> /dev/null; then
        # Use reflector to find country-specific mirrors, but prepend geo mirror
        reflector --country "$MIRROR_COUNTRY" --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || {
            log_warning "reflector failed, using fallback mirrors"
        }
        # Prepend geo mirror to the list
        sed -i "1i $geo_mirror" /etc/pacman.d/mirrorlist
    else
        # Use reliable fallback mirrors (geo-balanced + major US mirrors)
        cat > /etc/pacman.d/mirrorlist << 'MIRRORS'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirrors.rit.edu/archlinux/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://mirror.lty.me/archlinux/$repo/os/$arch
MIRRORS
    fi
    log_success "Mirror list optimized"

    # Create vconsole.conf BEFORE pacstrap to avoid mkinitcpio warnings
    mkdir -p /mnt/etc
    echo "KEYMAP=${KEYMAP}" > /mnt/etc/vconsole.conf
    log_success "vconsole.conf pre-created"

    # Install base system with download timeout disabled for slow connections.
    # `linux-lts` is included as a fallback kernel — if a future `pacman -Syu`
    # pulls a broken `linux` (e.g. v7 mismatch), the user can boot LTS from
    # the GRUB menu and recover. Standard Arch best practice.
    log_step "Running pacstrap (downloading ~1GB — base + linux + linux-lts)..."
    if ! pacstrap -K /mnt \
        base \
        base-devel \
        linux \
        linux-lts \
        linux-firmware \
        linux-headers \
        linux-lts-headers \
        intel-ucode \
        amd-ucode \
        networkmanager \
        grub \
        efibootmgr \
        os-prober \
        sudo \
        vim \
        nano \
        git \
        curl \
        wget \
        aria2 \
        htop \
        fastfetch \
        zsh \
        man-db \
        man-pages \
        texinfo \
        openssh \
        reflector
    then
        die "pacstrap failed — base system did not install. Cannot continue."
    fi

    log_success "Base system installed (linux + linux-lts as fallback)"

    # Copy optimized mirrorlist to new system
    cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

    # Mirror the pacman.conf tuning into the target system AND defensively pin
    # the kernel during the install. The IgnorePkg line prevents any subsequent
    # `pacman -Syu` (run inside chroot during config) from yanking `linux` out
    # from under a running ISO that has older kernel headers — the exact failure
    # path that bricks NVIDIA/DKMS installs mid-flight.
    log_step "Tuning target pacman.conf (parallel + aria2 + kernel pin)..."
    if ! grep -q '^ParallelDownloads' /mnt/etc/pacman.conf; then
        sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 8/' /mnt/etc/pacman.conf
        grep -q '^ParallelDownloads' /mnt/etc/pacman.conf || \
            echo 'ParallelDownloads = 8' >> /mnt/etc/pacman.conf
    fi
    if ! grep -q '^XferCommand' /mnt/etc/pacman.conf; then
        sed -i '/^\[options\]/a XferCommand = /usr/bin/aria2c --allow-overwrite=true --continue=true --file-allocation=none --log-level=error --max-tries=4 --max-connection-per-server=8 --max-file-not-found=4 --min-split-size=5M --no-conf --remote-time=true --summary-interval=60 --timeout=10 --retry-wait=1 --console-log-level=error --download-result=hide --quiet -d / -o %o %u' /mnt/etc/pacman.conf
    fi
    if ! grep -q '^IgnorePkg.*linux' /mnt/etc/pacman.conf; then
        sed -i '/^\[options\]/a IgnorePkg   = linux linux-headers linux-firmware linux-lts linux-lts-headers' /mnt/etc/pacman.conf
    fi
    log_success "Target pacman tuned + kernel pinned for install duration"

    # Generate fstab
    log_step "Generating fstab..."
    if ! genfstab -U /mnt >> /mnt/etc/fstab; then
        die "fstab generation failed — system would not mount on boot."
    fi
    log_success "fstab generated"
}

# ============================================================================
# System Configuration (chroot)
# ============================================================================

configure_system() {
    log_step "Configuring system..."

    # Create configuration script to run inside chroot.
    # NOTE: no `set -e`. Each command checks $? and either retries / warns /
    # falls back. The only fatal step is GRUB install — without it the system
    # won't boot, so we explicitly exit 1 there.
    cat > /mnt/root/chroot-setup.sh << CHROOT_EOF
#!/bin/bash
# Don't bail on first error — continue and report.
set +e

CHROOT_FAILS=0
chroot_warn() { echo "  ⚠ \$1 failed (rc=\$?)" >&2; CHROOT_FAILS=\$((CHROOT_FAILS+1)); }

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime || chroot_warn "timezone link"
hwclock --systohc || chroot_warn "hwclock"

# Locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
if [ "${LOCALE}" != "en_US.UTF-8" ]; then
    echo "${LOCALE} UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

# Keymap
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

# Root password (same as user for simplicity)
echo "root:${USER_PASSWORD}" | chpasswd

# Create user
useradd -m -G wheel,audio,video,storage,optical -s /bin/zsh ${USERNAME}
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# Sudo access
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Enable services
systemctl enable NetworkManager
systemctl enable fstrim.timer

# Install GRUB. This IS fatal — without it the system won't boot. Try once,
# retry once with --no-nvram for stubborn UEFI firmware, then bail.
if ! grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=JesterNet --removable; then
    echo "  ⚠ first grub-install failed — retrying with --no-nvram"
    if ! grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=JesterNet --removable --no-nvram; then
        echo "  ✗ grub-install failed twice — system will not boot"
        exit 1
    fi
fi
grub-mkconfig -o /boot/grub/grub.cfg || { echo "  ✗ grub-mkconfig failed"; exit 1; }

# Create initial ramdisk for both kernels — failure here = unbootable system.
if ! mkinitcpio -P; then
    echo "  ✗ mkinitcpio failed — initramfs not generated"
    exit 1
fi

if [ "\$CHROOT_FAILS" -gt 0 ]; then
    echo "Base configuration complete with \$CHROOT_FAILS non-fatal warnings (see above)"
else
    echo "Base configuration complete"
fi
CHROOT_EOF

    chmod +x /mnt/root/chroot-setup.sh
    if ! arch-chroot /mnt /bin/bash /root/chroot-setup.sh; then
        die "chroot-setup.sh hit a fatal error (bootloader/initramfs). System will not boot."
    fi

    log_success "System configured"
}

# ============================================================================
# GNOME Desktop Installation
# ============================================================================

install_desktop() {
    log_step "Installing GNOME desktop environment..."

    # NOTE: no `set -e`. If a single package group fails (e.g. AUR sync, mirror
    # hiccup), the rest still install. We retry once with --refresh on group
    # failure to recover from stale package metadata — the second-most-common
    # failure mode after kernel mismatch.
    cat > /mnt/root/install-desktop.sh << 'DESKTOP_EOF'
#!/bin/bash
set +e
DESKTOP_FAILS=0

# Helper: try a pacman group, retry once with --refresh if it fails.
try_group() {
    local label="$1"; shift
    if pacman -S --noconfirm --needed "$@"; then
        return 0
    fi
    echo "  ⚠ $label failed first attempt — refreshing mirrors and retrying"
    pacman -Syy --noconfirm
    if pacman -S --noconfirm --needed "$@"; then
        return 0
    fi
    echo "  ✗ $label failed twice — continuing without it"
    DESKTOP_FAILS=$((DESKTOP_FAILS+1))
    return 1
}

# Install GNOME and essentials
try_group "GNOME core" \
    gnome gnome-tweaks gnome-shell-extensions gdm gnome-browser-connector \
    dconf-editor file-roller evince gnome-calculator gnome-calendar \
    gnome-clocks gnome-font-viewer gnome-logs gnome-system-monitor \
    gnome-weather gnome-disk-utility baobab loupe gedit

# Audio (PipeWire) - --ask 4 auto-resolves conflicts (e.g. jack2 vs pipewire-jack)
pacman -S --noconfirm --needed --ask 4 \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber pavucontrol \
    || { echo "  ⚠ PipeWire stack failed — sound may not work"; DESKTOP_FAILS=$((DESKTOP_FAILS+1)); }

# Fonts
try_group "fonts" \
    ttf-dejavu ttf-liberation noto-fonts noto-fonts-emoji ttf-fira-code ttf-jetbrains-mono

# Essential apps
try_group "essential apps" \
    firefox kitty thunar nautilus gnome-terminal

# GTK Themes (Orchis)
try_group "GTK theme deps" \
    gtk-engine-murrine sassc

# Enable GDM (must succeed for graphical login to work)
if ! systemctl enable gdm; then
    echo "  ⚠ failed to enable gdm — log in via tty, then 'systemctl enable gdm' manually"
    DESKTOP_FAILS=$((DESKTOP_FAILS+1))
fi

if [ "$DESKTOP_FAILS" -gt 0 ]; then
    echo "Desktop install complete with $DESKTOP_FAILS issues — see above"
    exit 0  # still don't propagate failure; GNOME core may have worked
fi
echo "Desktop installation complete"
DESKTOP_EOF

    chmod +x /mnt/root/install-desktop.sh
    if ! arch-chroot /mnt /bin/bash /root/install-desktop.sh; then
        log_warning "Desktop install reported failures — system will boot but may need manual fixes"
        FAILED_STEPS+=("desktop install (some packages)")
    fi

    log_success "GNOME desktop install phase complete"
}

# ============================================================================
# JesterNet Theme Installation
# ============================================================================

install_jesternet_theme() {
    log_step "Installing JesterNet DarkGlass theme..."

    # Copy theme files to new system
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    THEME_DIR="$(dirname "$SCRIPT_DIR")"

    # Copy entire theme package
    mkdir -p /mnt/home/${USERNAME}/JesterNet
    cp -r "$THEME_DIR"/* /mnt/home/${USERNAME}/JesterNet/ 2>/dev/null || {
        log_warning "Theme files not found locally, will need manual installation"
        return
    }

    # Install DarkGlass icon theme system-wide
    if [ -d "$THEME_DIR/icons/DarkGlass" ]; then
        mkdir -p /mnt/usr/share/icons
        cp -r "$THEME_DIR/icons/DarkGlass" /mnt/usr/share/icons/
        log_success "DarkGlass icons installed"
    fi

    # Install GTK theme if present
    if [ -d "$THEME_DIR/gtk" ]; then
        mkdir -p /mnt/usr/share/themes
        cp -r "$THEME_DIR/gtk"/* /mnt/usr/share/themes/ 2>/dev/null || true
    fi

    # Install GNOME Shell theme if present
    if [ -d "$THEME_DIR/gnome-shell" ]; then
        mkdir -p /mnt/usr/share/gnome-shell/theme
        cp -r "$THEME_DIR/gnome-shell"/* /mnt/usr/share/gnome-shell/theme/ 2>/dev/null || true
    fi

    # Set up default wallpaper
    if [ -f "$THEME_DIR/config/wallpaper.jpg" ]; then
        mkdir -p /mnt/home/${USERNAME}/.config
        cp "$THEME_DIR/config/wallpaper.jpg" /mnt/home/${USERNAME}/.config/background
        log_success "Wallpaper installed"
    fi

    # Install GNOME extensions (user-level)
    mkdir -p /mnt/home/${USERNAME}/.local/share/gnome-shell/extensions

    # Copy all bundled extensions
    if [ -d "$THEME_DIR/extensions" ]; then
        cp -r "$THEME_DIR/extensions"/* /mnt/home/${USERNAME}/.local/share/gnome-shell/extensions/
        log_success "GNOME extensions installed"
    fi

    # Also copy darkglass-themer if in root (legacy location)
    if [ -d "$THEME_DIR/darkglass-themer@jesternet.com" ]; then
        cp -r "$THEME_DIR/darkglass-themer@jesternet.com" /mnt/home/${USERNAME}/.local/share/gnome-shell/extensions/
    fi

    # Create first-login setup script
    cat > /mnt/home/${USERNAME}/setup-theme.sh << 'THEME_EOF'
#!/bin/bash
# JesterNet Theme Setup - Run after first login

echo "Setting up JesterNet DarkGlass theme..."

# Install Orchis GTK theme from AUR (if yay is installed)
if command -v yay &> /dev/null; then
    yay -S --noconfirm orchis-theme 2>/dev/null || true
fi

# Install GNOME extensions from AUR
if command -v yay &> /dev/null; then
    yay -S --noconfirm --needed \
        gnome-shell-extension-dash-to-dock \
        gnome-shell-extension-blur-my-shell \
        gnome-shell-extension-just-perfection-desktop \
        2>/dev/null || true
fi

# Apply GNOME settings
gsettings set org.gnome.desktop.interface gtk-theme 'Orchis-Dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'DarkGlass' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.background picture-uri "file://$HOME/.config/background"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/.config/background"

# Enable all installed extensions
echo "Enabling extensions..."
for ext_dir in ~/.local/share/gnome-shell/extensions/*/; do
    ext_name=$(basename "$ext_dir")
    gnome-extensions enable "$ext_name" 2>/dev/null && echo "  ✓ $ext_name" || true
done

# Also enable system extensions
gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com 2>/dev/null || true

echo ""
echo "Theme setup complete!"
echo "Please log out and back in for all changes to take effect."
THEME_EOF

    chmod +x /mnt/home/${USERNAME}/setup-theme.sh
    arch-chroot /mnt chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/JesterNet
    arch-chroot /mnt chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.local
    arch-chroot /mnt chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
    arch-chroot /mnt chown ${USERNAME}:${USERNAME} /home/${USERNAME}/setup-theme.sh

    # Create autostart entry for first login (runs setup-theme.sh once then disables itself)
    mkdir -p /mnt/home/${USERNAME}/.config/autostart
    cat > /mnt/home/${USERNAME}/.config/autostart/jesternet-first-login.desktop << 'AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Name=JesterNet First Login Setup
Comment=Sets up JesterNet theme on first login
Exec=/bin/bash -c 'if [ -f "$HOME/setup-theme.sh" ]; then gnome-terminal -- bash -c "$HOME/setup-theme.sh; echo Press Enter to close; read"; rm -f "$HOME/.config/autostart/jesternet-first-login.desktop"; fi'
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF

    arch-chroot /mnt chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config/autostart

    log_success "JesterNet theme files installed (will auto-setup on first login)"
}

# ============================================================================
# Development Stacks Installation
# ============================================================================

install_dev_stacks() {
    if [ -z "$DEV_STACKS" ]; then
        return
    fi

    log_step "Installing development stacks..."

    # Create installation script
    cat > /mnt/home/${USERNAME}/install-dev-stacks.sh << STACKS_EOF
#!/bin/bash
# Run this after first login to install development stacks
cd ~/JesterNet

STACKS_EOF

    for stack in $DEV_STACKS; do
        case "$stack" in
            tauri)   echo "./dev-stacks/tauri-stack.sh" >> /mnt/home/${USERNAME}/install-dev-stacks.sh ;;
            android) echo "./dev-stacks/android-stack.sh" >> /mnt/home/${USERNAME}/install-dev-stacks.sh ;;
            go)      echo "./dev-stacks/go-stack.sh" >> /mnt/home/${USERNAME}/install-dev-stacks.sh ;;
            python)  echo "./dev-stacks/python-stack.sh" >> /mnt/home/${USERNAME}/install-dev-stacks.sh ;;
            zig)     echo "./dev-stacks/zig-stack.sh" >> /mnt/home/${USERNAME}/install-dev-stacks.sh ;;
            web)     echo "./dev-stacks/web-stack.sh" >> /mnt/home/${USERNAME}/install-dev-stacks.sh ;;
            office)  echo "./dev-stacks/office-multimedia.sh" >> /mnt/home/${USERNAME}/install-dev-stacks.sh ;;
            creator) echo "./dev-stacks/content-creator.sh" >> /mnt/home/${USERNAME}/install-dev-stacks.sh ;;
        esac
    done

    chmod +x /mnt/home/${USERNAME}/install-dev-stacks.sh
    arch-chroot /mnt chown ${USERNAME}:${USERNAME} /home/${USERNAME}/install-dev-stacks.sh

    log_success "Development stack installer created"
}

# ============================================================================
# Enterprise Configuration
# ============================================================================

configure_enterprise() {
    log_step "Applying enterprise configuration..."

    # Static IP configuration
    if [ -n "$STATIC_IP" ] && [ -n "$GATEWAY" ]; then
        log_step "Configuring static IP: $STATIC_IP"

        # Get the primary network interface
        local iface=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(en|eth)' | head -1)

        cat > /mnt/etc/NetworkManager/system-connections/static.nmconnection << NMEOF
[connection]
id=static
type=ethernet
interface-name=${iface}
autoconnect=true

[ipv4]
method=manual
addresses=${STATIC_IP}
gateway=${GATEWAY}
dns=${DNS_SERVERS:-8.8.8.8;8.8.4.4}

[ipv6]
method=auto
NMEOF
        chmod 600 /mnt/etc/NetworkManager/system-connections/static.nmconnection
        log_success "Static IP configured"
    fi

    # Proxy configuration
    if [ -n "$HTTP_PROXY" ]; then
        log_step "Configuring proxy..."
        cat >> /mnt/etc/environment << PROXYEOF
http_proxy=${HTTP_PROXY}
https_proxy=${HTTPS_PROXY:-$HTTP_PROXY}
HTTP_PROXY=${HTTP_PROXY}
HTTPS_PROXY=${HTTPS_PROXY:-$HTTP_PROXY}
no_proxy=localhost,127.0.0.1,::1
PROXYEOF
        log_success "Proxy configured"
    fi

    # SSH configuration
    if [ "$SSH_ENABLED" = "true" ]; then
        log_step "Enabling SSH server..."
        arch-chroot /mnt systemctl enable sshd

        # Inject authorized keys if provided
        if [ -n "$SSH_AUTHORIZED_KEYS" ] && [ -f "$SSH_AUTHORIZED_KEYS" ]; then
            mkdir -p /mnt/home/${USERNAME}/.ssh
            cp "$SSH_AUTHORIZED_KEYS" /mnt/home/${USERNAME}/.ssh/authorized_keys
            chmod 700 /mnt/home/${USERNAME}/.ssh
            chmod 600 /mnt/home/${USERNAME}/.ssh/authorized_keys
            arch-chroot /mnt chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh
            log_success "SSH authorized keys injected"
        fi
        log_success "SSH server enabled"
    fi

    # Domain join preparation (AD/LDAP)
    if [ "$DOMAIN_JOIN_PREP" = "true" ]; then
        log_step "Installing domain join packages..."
        arch-chroot /mnt pacman -S --noconfirm --needed \
            sssd \
            realmd \
            krb5 \
            samba \
            oddjob \
            oddjob-mkhomedir \
            adcli \
            openldap-clients

        # Pre-configure realm if provided
        if [ -n "$DOMAIN_REALM" ]; then
            cat > /mnt/etc/krb5.conf.d/domain.conf << KRBEOF
[realms]
${DOMAIN_REALM} = {
    kdc = ${DOMAIN_REALM,,}
    admin_server = ${DOMAIN_REALM,,}
}

[domain_realm]
.${DOMAIN_REALM,,} = ${DOMAIN_REALM}
${DOMAIN_REALM,,} = ${DOMAIN_REALM}
KRBEOF
        fi
        log_success "Domain join packages installed"
    fi

    # Run post-install hook if provided
    if [ -n "$POST_INSTALL_HOOK" ] && [ -f "$POST_INSTALL_HOOK" ]; then
        log_step "Running post-install hook..."
        cp "$POST_INSTALL_HOOK" /mnt/root/post-install-hook.sh
        chmod +x /mnt/root/post-install-hook.sh
        arch-chroot /mnt /bin/bash /root/post-install-hook.sh
        rm -f /mnt/root/post-install-hook.sh
        log_success "Post-install hook completed"
    fi

    log_success "Enterprise configuration applied"
}

# ============================================================================
# AUR Helper Installation
# ============================================================================

install_aur_helper() {
    log_step "Installing yay (AUR helper)..."

    # yay must be built as a regular user, so create a first-boot script.
    # Tolerant: each step checks rc, network failure → retry once, build
    # failure → leave dir for manual recovery instead of vanishing silently.
    cat > /mnt/home/${USERNAME}/install-yay.sh << 'YAY_USER_EOF'
#!/bin/bash
set +e
cd /tmp || exit 1
rm -rf yay 2>/dev/null

# Retry git clone once on network blip
for attempt in 1 2; do
    if git clone https://aur.archlinux.org/yay.git; then
        break
    fi
    echo "git clone failed (attempt $attempt) — retrying in 3s"
    sleep 3
    rm -rf yay 2>/dev/null
done

if [ ! -d /tmp/yay ]; then
    echo "✗ Could not clone yay AUR repo. Run this script again with internet access."
    exit 1
fi

cd yay || exit 1
if makepkg -si --noconfirm; then
    cd .. && rm -rf yay
    echo "✓ yay installed successfully!"

    # Once yay is in, pull the AUR-only terminal: Warp.
    # Non-fatal — user can retry later with: yay -S warp-terminal-bin
    echo ""
    echo "Installing Warp terminal from AUR..."
    if yay -S --noconfirm --needed warp-terminal-bin; then
        echo "✓ Warp terminal installed."
    else
        echo "⚠ Warp install failed. Retry manually with: yay -S warp-terminal-bin"
    fi

    exit 0
else
    cd ..
    echo "⚠ yay build failed. Source left in /tmp/yay for manual fix-up:"
    echo "    cd /tmp/yay && makepkg -si --noconfirm"
    exit 1
fi
YAY_USER_EOF

    chmod +x /mnt/home/${USERNAME}/install-yay.sh
    arch-chroot /mnt chown ${USERNAME}:${USERNAME} /home/${USERNAME}/install-yay.sh

    log_success "AUR helper installer created"
}

# ============================================================================
# Terminal Stack
# ----------------------------------------------------------------------------
# Installs a curated terminal environment: zsh + plugins, tmux, two GPU
# terminals (WezTerm, Ghostty), and JetBrains Mono. Warp is queued for the
# post-boot install-yay.sh step because it's AUR-only.
# ============================================================================

install_terminal_stack() {
    log_step "Installing terminal stack (zsh, tmux, WezTerm, Ghostty)..."

    # Official-repo packages — Warp is AUR and handled in install-yay.sh tail.
    # Three groups, ordered by purpose for review at a glance:
    #   shells/multiplexer/terminals/fonts → modern CLI replacements → wow utils
    if ! arch-chroot /mnt pacman -S --needed --noconfirm \
            zsh tmux \
            wezterm ghostty \
            zsh-fast-syntax-highlighting zsh-autosuggestions zsh-completions \
            ttf-jetbrains-mono ttf-jetbrains-mono-nerd ttf-fira-code \
            starship fzf eza bat fd ripgrep zoxide git-delta \
            btop duf dust tealdeer fastfetch onefetch; then
        log_warning "Some terminal packages failed to install — continuing"
    fi

    # Make zsh the user's login shell. chsh failure is non-fatal — user can
    # rerun the command themselves. We use absolute path because /etc/shells
    # may not yet be fully populated for fresh root chroots.
    if ! arch-chroot /mnt chsh -s /usr/bin/zsh "${USERNAME}" 2>/dev/null; then
        log_warning "chsh failed — user can run: chsh -s /usr/bin/zsh"
    fi

    mkdir -p "/mnt/home/${USERNAME}/.config/wezterm"
    mkdir -p "/mnt/home/${USERNAME}/.config/ghostty"

    # ------------------------------------------------------------------
    # ~/.zshrc
    # ------------------------------------------------------------------
    cat > "/mnt/home/${USERNAME}/.zshrc" << 'ZSHRC_EOF'
# JesterNet OS — zsh starter config
# Pulls together the modern shell stack: starship prompt, fzf fuzzy
# finder, zoxide smart-cd, eza/bat/fd/ripgrep, plus zsh autosuggestions
# and fast-syntax-highlighting. Extend freely.

# ---- History --------------------------------------------------------------
HISTFILE=~/.histfile
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE INC_APPEND_HISTORY EXTENDED_HISTORY

# ---- Word boundaries ------------------------------------------------------
# Stop treating / and . as word characters so Alt-B / Alt-F jump path segments.
WORDCHARS=${WORDCHARS//[\/\.]}

# ---- Completion -----------------------------------------------------------
if [[ -d /usr/share/zsh/site-functions ]]; then
    fpath=(/usr/share/zsh/site-functions $fpath)
fi
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# ---- Plugins (load order matters) -----------------------------------------
# zsh-autosuggestions: ghostly inline preview from history.
[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6272a4'

# fzf: Ctrl-R fuzzy history, Ctrl-T fuzzy file picker, Alt-C fuzzy cd.
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -r /usr/share/fzf/completion.zsh   ]] && source /usr/share/fzf/completion.zsh

# zoxide: `z foo` to jump to any dir you've visited; `zi foo` for interactive picker.
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# fast-syntax-highlighting: MUST come after other plugins that bind keymaps,
# otherwise its hooks miss those bindings.
[[ -r /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh ]] && \
    source /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh

# ---- Modern CLI replacements ---------------------------------------------
if command -v eza >/dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -lah --icons --git --group-directories-first'
    alias la='eza -a --icons'
    alias tree='eza --tree --icons --git-ignore'
fi
command -v bat  >/dev/null && export BAT_THEME='Dracula'
command -v duf  >/dev/null && alias df='duf'
command -v dust >/dev/null && alias du='dust'

# ---- fzf: JesterNet palette + fd as default file source ------------------
if command -v fd >/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi
export FZF_DEFAULT_OPTS="
  --height=40% --layout=reverse --border=rounded
  --color=bg+:#1a1a25,bg:#0a0a0f,spinner:#00ffff,hl:#ff00ff
  --color=fg:#f8f8f2,header:#ff00ff,info:#00ffff,pointer:#00ffff
  --color=marker:#00ffff,fg+:#f8f8f2,prompt:#ff00ff,hl+:#ff00ff"

# ---- Other aliases --------------------------------------------------------
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias rg='rg --smart-case'

# ---- Starship prompt — must run last (it sets PROMPT/RPROMPT) -----------
command -v starship >/dev/null && eval "$(starship init zsh)"

# Uncomment for vi-mode:
# bindkey -v
ZSHRC_EOF

    # ------------------------------------------------------------------
    # ~/.tmux.conf
    # ------------------------------------------------------------------
    cat > "/mnt/home/${USERNAME}/.tmux.conf" << 'TMUX_EOF'
# JesterNet OS — tmux starter config

# Prefix: Ctrl-Space (avoids the C-b that breaks vim, and the C-a that breaks readline).
unbind C-b
set -g prefix C-Space
bind C-Space send-prefix

# Mouse + true color
set -g mouse on
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:RGB,*:RGB"

# Generous scrollback and snappy escape.
set -g history-limit 50000
set -sg escape-time 10

# vi-mode for copy mode.
setw -g mode-keys vi

# 1-indexed windows/panes; renumber on close.
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on

# Reload config in place.
bind r source-file ~/.tmux.conf \; display "Reloaded ~/.tmux.conf"

# Splits open in the current pane's working directory.
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# JesterNet cyan/magenta status bar.
set -g status-bg "#0a0a0f"
set -g status-fg "#bfbfbf"
set -g status-left-length 30
set -g status-left  "#[fg=#00ffff,bold] #S #[fg=#ff00ff]│ "
set -g status-right "#[fg=#ff00ff]│ #[fg=#00ffff]%H:%M #[fg=#ff00ff]│ #[fg=#00ffff]%d-%b "
setw -g window-status-current-style "fg=#00ffff,bold"
setw -g window-status-style         "fg=#6272a4"
set -g pane-active-border-style     "fg=#00ffff"
set -g pane-border-style            "fg=#1a1a25"
TMUX_EOF

    # ------------------------------------------------------------------
    # ~/.config/wezterm/wezterm.lua  — JesterNet theme + transparency
    # ------------------------------------------------------------------
    cat > "/mnt/home/${USERNAME}/.config/wezterm/wezterm.lua" << 'WEZTERM_EOF'
-- JesterNet OS — WezTerm config
-- Cyan/magenta cyberpunk palette, glassmorphic transparency, JetBrains Mono.

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ---- Palette --------------------------------------------------------------
config.colors = {
  foreground     = '#f8f8f2',
  background     = '#0a0a0f',
  cursor_bg      = '#00ffff',
  cursor_fg      = '#0a0a0f',
  cursor_border  = '#00ffff',
  selection_bg   = '#ff00ff',
  selection_fg   = '#0a0a0f',
  ansi = {
    '#14141e', '#ff5577', '#50fa7b', '#f1fa8c',
    '#6272a4', '#ff00ff', '#00ffff', '#bfbfbf',
  },
  brights = {
    '#44475a', '#ff7799', '#69ff94', '#ffffa5',
    '#7e8eb6', '#ff77ff', '#77ffff', '#ffffff',
  },
  tab_bar = {
    background   = '#0a0a0f',
    active_tab   = { bg_color = '#1a1a25', fg_color = '#00ffff' },
    inactive_tab = { bg_color = '#0a0a0f', fg_color = '#6272a4' },
  },
}

-- ---- Font -----------------------------------------------------------------
-- Nerd Font first so starship icons + eza icons render correctly. Falls back
-- to plain JetBrains Mono / Fira Code if the nerd-font package isn't present.
config.font = wezterm.font_with_fallback {
  'JetBrainsMono Nerd Font',
  'JetBrains Mono',
  'Fira Code',
  'monospace',
}
config.font_size = 11.0
config.line_height = 1.05

-- ---- Window ---------------------------------------------------------------
config.window_background_opacity = 0.85
config.window_padding = { left = 12, right = 12, top = 8, bottom = 8 }
config.window_decorations = 'RESIZE'
config.use_fancy_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true

-- ---- Cursor / behavior ----------------------------------------------------
config.default_cursor_style = 'BlinkingBlock'
config.cursor_blink_rate    = 600
config.scrollback_lines     = 50000
config.audible_bell         = 'Disabled'

return config
WEZTERM_EOF

    # ------------------------------------------------------------------
    # ~/.config/ghostty/config — same palette, ghostty syntax
    # ------------------------------------------------------------------
    cat > "/mnt/home/${USERNAME}/.config/ghostty/config" << 'GHOSTTY_EOF'
# JesterNet OS — Ghostty config

background = #0a0a0f
foreground = #f8f8f2
background-opacity = 0.85
background-blur-radius = 20

cursor-color = #00ffff
cursor-style = block
cursor-style-blink = true

selection-background = #ff00ff
selection-foreground = #0a0a0f

# 16-color ANSI — JesterNet cyan/magenta accents
palette = 0=#14141e
palette = 1=#ff5577
palette = 2=#50fa7b
palette = 3=#f1fa8c
palette = 4=#6272a4
palette = 5=#ff00ff
palette = 6=#00ffff
palette = 7=#bfbfbf
palette = 8=#44475a
palette = 9=#ff7799
palette = 10=#69ff94
palette = 11=#ffffa5
palette = 12=#7e8eb6
palette = 13=#ff77ff
palette = 14=#77ffff
palette = 15=#ffffff

font-family = JetBrainsMono Nerd Font
font-size = 11

window-padding-x = 12
window-padding-y = 8
GHOSTTY_EOF

    # ------------------------------------------------------------------
    # ~/.config/starship.toml — JesterNet-themed prompt
    # ------------------------------------------------------------------
    cat > "/mnt/home/${USERNAME}/.config/starship.toml" << 'STARSHIP_EOF'
# JesterNet OS — starship prompt
# Cyan/magenta cyberpunk; Nerd Font glyphs throughout (icons render
# only if the terminal is using the nerd-font variant of JetBrains Mono).

format = """
[╭─](bold magenta)$username$hostname$directory$git_branch$git_status$rust$python$nodejs$golang$cmd_duration
[╰─](bold magenta)$character"""

add_newline = false

[character]
success_symbol = "[❯](bold cyan)"
error_symbol   = "[❯](bold red)"
vimcmd_symbol  = "[❮](bold green)"

[username]
style_user = "bold cyan"
style_root = "bold red"
format     = "[$user]($style)"
show_always = false

[hostname]
ssh_only = false
style    = "bold cyan"
format   = "[@$hostname]($style) "

[directory]
style              = "bold cyan"
format             = "[$path]($style) "
truncation_length  = 5
truncate_to_repo   = true
read_only          = " "

[git_branch]
symbol = " "
style  = "bold magenta"
format = "[$symbol$branch]($style) "

[git_status]
style  = "bold magenta"
format = "[$all_status$ahead_behind]($style) "
ahead     = "⇡${count}"
behind    = "⇣${count}"
diverged  = "⇕⇡${ahead_count}⇣${behind_count}"
conflicted = "="
untracked  = "?${count}"
modified   = "!${count}"
staged     = "+${count}"
renamed    = "»${count}"
deleted    = "✘${count}"
stashed    = "$"

[cmd_duration]
min_time = 2000
style    = "bold yellow"
format   = "[took $duration]($style) "

[rust]
symbol = " "
style  = "bold #ff5577"
format = "[$symbol$version]($style) "

[python]
symbol = " "
style  = "bold yellow"
format = "[$symbol$version]($style) "

[nodejs]
symbol = " "
style  = "bold green"
format = "[$symbol$version]($style) "

[golang]
symbol = " "
style  = "bold cyan"
format = "[$symbol$version]($style) "

[package]
disabled = true
STARSHIP_EOF

    # ------------------------------------------------------------------
    # ~/.zlogin — runs once per login shell. fastfetch shows a quick
    # ASCII splash with system info — this is the "wow" first-boot moment
    # for users coming from Windows. Skipped silently in nested shells.
    # ------------------------------------------------------------------
    cat > "/mnt/home/${USERNAME}/.zlogin" << 'ZLOGIN_EOF'
# Run only on real interactive login shells (not on every nested zsh).
if [[ -o login && -t 1 ]] && command -v fastfetch >/dev/null; then
    fastfetch
fi
ZLOGIN_EOF

    # ------------------------------------------------------------------
    # ~/.gitconfig — only seeded if the user doesn't already have one.
    # Sets up git-delta for pretty side-by-side diffs and useful colors.
    # User identity (name/email) is intentionally NOT set; the user runs
    # `git config --global user.name/email` themselves.
    # ------------------------------------------------------------------
    if [[ ! -f "/mnt/home/${USERNAME}/.gitconfig" ]]; then
        cat > "/mnt/home/${USERNAME}/.gitconfig" << 'GITCONFIG_EOF'
# JesterNet OS — git starter config
# Set your identity:
#   git config --global user.name  "Your Name"
#   git config --global user.email "you@example.com"

[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    features = side-by-side line-numbers decorations
    syntax-theme = Dracula
    navigate = true

[delta "decorations"]
    commit-decoration-style = bold magenta box ul
    file-style = bold cyan ul
    file-decoration-style = none
    hunk-header-decoration-style = cyan box

[merge]
    conflictstyle = diff3

[diff]
    colorMoved = default

[init]
    defaultBranch = main

[pull]
    rebase = false
GITCONFIG_EOF
    fi

    # Single chown sweep — covers the four direct-home files plus the .config
    # subdirs we created. Recursive on .config is safe here because GNOME
    # hasn't run yet, so nothing else owns subdirs there.
    arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" \
        "/home/${USERNAME}/.zshrc" \
        "/home/${USERNAME}/.zlogin" \
        "/home/${USERNAME}/.tmux.conf" \
        "/home/${USERNAME}/.gitconfig" \
        "/home/${USERNAME}/.config" 2>/dev/null || true

    log_success "Terminal stack installed (Warp queued for post-boot AUR install)"
}

# ============================================================================
# Final Cleanup
# ============================================================================

cleanup() {
    log_step "Cleaning up..."

    # Remove temporary scripts
    rm -f /mnt/root/chroot-setup.sh
    rm -f /mnt/root/install-desktop.sh

    # Install the system baseline tool to the user's home so it's available
    # alongside the other first-login scripts (./install-yay.sh, etc.).
    local CLEANUP_SCRIPT_DIR
    CLEANUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$CLEANUP_SCRIPT_DIR/linux-baseline.sh" ]; then
        cp "$CLEANUP_SCRIPT_DIR/linux-baseline.sh" /mnt/home/${USERNAME}/linux-baseline.sh
        chmod +x /mnt/home/${USERNAME}/linux-baseline.sh
        arch-chroot /mnt chown ${USERNAME}:${USERNAME} /home/${USERNAME}/linux-baseline.sh
    fi

    # Create first-boot instruction file
    cat > /mnt/home/${USERNAME}/FIRST_BOOT_README.txt << README_EOF
╔══════════════════════════════════════════════════════════════════════════╗
║                    WELCOME TO JESTERNET OS                               ║
╚══════════════════════════════════════════════════════════════════════════╝

Congratulations! Your JesterNet OS installation is complete.

After logging in, run these commands to complete your setup:

Pre-installed terminal stack (already in /usr/bin):
   Shell:       zsh (default)  ·  tmux  ·  starship prompt
   Terminals:   WezTerm  ·  Ghostty   (Warp installs in step 1 below)
   Modern CLI:  eza · bat · fd · ripgrep · zoxide · fzf · git-delta
   Wow utils:   btop · duf · dust · fastfetch · onefetch · tealdeer

   Try right now:
     fastfetch                # ASCII splash + system info (auto-runs on login)
     btop                     # system monitor
     z <dirname>              # smart-cd via zoxide
     Ctrl-R                   # fzf fuzzy history search
     ll                       # eza with icons + git status
     bat <file>               # syntax-highlighted cat
     onefetch                 # repo info, run inside any git repo

   Configs:    ~/.zshrc · ~/.tmux.conf · ~/.gitconfig
               ~/.config/{wezterm,ghostty,starship.toml}

1. Install yay + Warp terminal (AUR):
   ./install-yay.sh
   (yay first, then warp-terminal-bin from AUR)

2. Apply the JesterNet theme:
   ./setup-theme.sh

3. Install development stacks (optional):
   ./install-dev-stacks.sh

4. Capture a system baseline (optional, ~90s):
   ./linux-baseline.sh
   Writes baseline-<host>-<UTC>.txt for diffing against future runs
   (kernel upgrades, governor changes, etc.). See README for details.

5. Reboot to apply all changes:
   reboot

Enjoy your new system!

─────────────────────────────────────────────────────────────────────────────
The Doctrine of Sovereign Artifacts is fulfilled.
README_EOF

    arch-chroot /mnt chown ${USERNAME}:${USERNAME} /home/${USERNAME}/FIRST_BOOT_README.txt

    # Unmount
    log_step "Unmounting partitions..."
    umount -R /mnt
    swapoff -a

    log_success "Installation complete!"
}

# ============================================================================
# Summary
# ============================================================================

print_summary() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}            INSTALLATION COMPLETE!${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Hostname:      $HOSTNAME"
    echo "  Username:      $USERNAME"
    echo "  Timezone:      $TIMEZONE"
    echo "  Desktop:       $DESKTOP_STYLE style"
    echo "  Dev Stacks:    ${DEV_STACKS:-none}"
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Remove the installation media"
    echo "  2. Reboot: ${GREEN}reboot${NC}"
    echo "  3. Log in as $USERNAME"
    echo "  4. Run: ${GREEN}./setup-theme.sh${NC}"
    echo ""
    echo -e "${YELLOW}Read ~/FIRST_BOOT_README.txt for complete instructions${NC}"
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_banner
    init_install_log     # set up persistent log before anything else
    preflight_checks
    select_disk
    configure_user
    select_desktop_style
    select_dev_stacks

    # Confirmation
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                    INSTALLATION SUMMARY${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Target Disk:   $TARGET_DISK"
    echo "  Hostname:      $HOSTNAME"
    echo "  Username:      $USERNAME"
    echo "  Timezone:      $TIMEZONE"
    echo "  Desktop:       $DESKTOP_STYLE"
    echo "  Dev Stacks:    ${DEV_STACKS:-none}"
    echo ""
    echo -e "${RED}WARNING: This will ERASE ALL DATA on $TARGET_DISK${NC}"
    echo ""

    # Auto-confirm if using config file, otherwise prompt
    if [ -n "$CONFIG_FILE" ]; then
        log_step "Auto-confirming installation from config file..."
        sleep 2
    else
        read -p "Begin installation? [y/N]: " final_confirm
        if [[ ! "$final_confirm" =~ ^[Yy]$ ]]; then
            echo "Installation cancelled"
            exit 0
        fi
    fi

    # Phases 1-3 are FATAL on failure — without them you have no bootable system.
    # Each calls `die` internally if it can't continue.
    prepare_clean_state    # recover from any prior failed run before touching disk
    partition_disk
    install_base_system
    configure_system

    # Phases 4-8 are RECOVERABLE — we soldier on through any of them failing.
    # Each is wrapped so a hiccup (mirror, package conflict, AUR network blip)
    # doesn't leave the user with a half-installed system. Failures get
    # collected into FAILED_STEPS for the end-of-install summary.
    try_func "Install GNOME desktop"     install_desktop
    try_func "Install JesterNet theme"   install_jesternet_theme
    try_func "Install dev stacks"        install_dev_stacks
    try_func "Apply enterprise config"   configure_enterprise
    try_func "Install terminal stack"    install_terminal_stack
    try_func "Install AUR helper (yay)"  install_aur_helper

    cleanup
    print_summary
    print_failure_summary
}

# ============================================================================
# Entry Point
# ============================================================================

# Check for optional config file argument. Use ${1:-} so set -u doesn't trip
# when the script is invoked without any arguments (the common case).
if [ -n "${1:-}" ] && [ -f "$1" ]; then
    CONFIG_FILE="$1"
    log_step "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
fi

main
