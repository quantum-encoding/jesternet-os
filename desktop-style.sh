#!/bin/bash
# ============================================================================
# Desktop Style Selector - JesterNet OS
# ============================================================================
# Choose between macOS-style Dock or Windows-style Taskbar
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

log_step() {
    echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo -e "${MAGENTA}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                   DESKTOP STYLE SELECTOR                         ║
║              Choose Your Preferred Workflow                      ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_dock_preview() {
    echo -e "${CYAN}"
    cat << 'EOF'
    ┌─────────────────────────────────────────────────────────────┐
    │  Activities                          🔊 🔋 📶  Mon 12:00    │
    ├─────────────────────────────────────────────────────────────┤
    │                                                             │
    │                                                             │
    │                      Your Desktop                           │
    │                                                             │
    │                                                             │
    ├─────────────────────────────────────────────────────────────┤
    │       🦊  📁  💻  🎵  ⚙️   |  📌 Running  |   🗑️            │
    │                      ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔                        │
    └─────────────────────────────────────────────────────────────┘
EOF
    echo -e "${NC}"
}

print_taskbar_preview() {
    echo -e "${BLUE}"
    cat << 'EOF'
    ┌─────────────────────────────────────────────────────────────┐
    │                                                             │
    │                                                             │
    │                      Your Desktop                           │
    │                                                             │
    │                                                             │
    ├─────────────────────────────────────────────────────────────┤
    │ ⬡ Apps │ 🦊 Firefox │ 📁 Files │ 💻 Term │   🔊 🔋 12:00   │
    └─────────────────────────────────────────────────────────────┘
EOF
    echo -e "${NC}"
}

# ============================================================================
# Extension Installation
# ============================================================================

check_gnome_extensions_cli() {
    if ! command -v gnome-extensions &> /dev/null; then
        log_error "gnome-extensions command not found"
        log_step "Installing gnome-shell-extensions..."
        sudo pacman -S --needed --noconfirm gnome-shell-extensions
    fi
}

install_extension_from_url() {
    local name="$1"
    local uuid="$2"
    local url="$3"

    log_step "Installing $name..."

    local ext_dir="$HOME/.local/share/gnome-shell/extensions/$uuid"

    if [ -f "$ext_dir/metadata.json" ]; then
        log_success "$name already installed"
        return 0
    fi

    local temp_zip
    temp_zip=$(mktemp --suffix=.zip)

    # -f makes HTTP errors fail instead of saving an error page as the zip
    if ! curl -fsSL -o "$temp_zip" "$url"; then
        log_error "Failed to download $name"
        rm -f "$temp_zip"
        return 1
    fi

    mkdir -p "$ext_dir"
    if ! unzip -qo "$temp_zip" -d "$ext_dir"; then
        log_error "Failed to extract $name"
        # Don't leave an empty dir behind, or the next run reports "already installed"
        rm -rf "$ext_dir" "$temp_zip"
        return 1
    fi

    rm -f "$temp_zip"
    log_success "$name installed"
}

# Resolve the extensions.gnome.org download URL for the running GNOME Shell
# major version, so we never pin a zip that only supports an older shell.
ego_download_url() {
    local pk="$1"
    local shell_major
    shell_major=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)

    local path
    path=$(curl -fsSL "https://extensions.gnome.org/extension-info/?pk=${pk}&shell_version=${shell_major}" \
        | grep -oE '"download_url": *"[^"]+"' | cut -d'"' -f4) || return 1

    [ -n "$path" ] || return 1
    echo "https://extensions.gnome.org${path}"
}

# Install from the Arch repos if packaged, otherwise from extensions.gnome.org.
install_extension() {
    local name="$1"
    local uuid="$2"
    local pkg="$3"
    local pk="$4"

    if pacman -Qi "$pkg" &> /dev/null; then
        log_success "$name already installed via pacman"
        return 0
    fi

    if pacman -Si "$pkg" &> /dev/null; then
        sudo pacman -S --needed --noconfirm "$pkg" && return 0
        log_warning "pacman install of $pkg failed, falling back to extensions.gnome.org"
    fi

    local url
    if ! url=$(ego_download_url "$pk"); then
        log_error "$name has no release for GNOME Shell $(gnome-shell --version | grep -oE '[0-9]+' | head -1)"
        echo -e "  ${CYAN}Visit:${NC} https://extensions.gnome.org/extension/${pk}/"
        return 1
    fi

    install_extension_from_url "$name" "$uuid" "$url"
}

# `gnome-extensions enable` only works on extensions the running shell has
# already loaded. On Wayland a freshly unpacked extension isn't loaded until
# the next login, so fall back to editing enabled-extensions directly.
enable_extension() {
    local uuid="$1"

    gnome-extensions enable "$uuid" 2>/dev/null && return 0

    local current
    current=$(gsettings get org.gnome.shell enabled-extensions)
    [[ "$current" == *"'$uuid'"* ]] && return 0

    if [[ "$current" == "@as []" || "$current" == "[]" ]]; then
        gsettings set org.gnome.shell enabled-extensions "['$uuid']"
    else
        gsettings set org.gnome.shell enabled-extensions "${current%]}, '$uuid']"
    fi
}

disable_extension() {
    local uuid="$1"

    gnome-extensions disable "$uuid" 2>/dev/null || true

    local current updated
    current=$(gsettings get org.gnome.shell enabled-extensions)
    [[ "$current" == *"'$uuid'"* ]] || return 0

    updated=$(echo "$current" | sed -e "s/'$uuid', //; s/, '$uuid'//; s/'$uuid'//")
    [[ "$updated" == "[]" ]] && updated="@as []"
    gsettings set org.gnome.shell enabled-extensions "$updated"
}

install_dash_to_dock() {
    log_step "Setting up Dash to Dock (macOS-style)..."
    # Not packaged in the Arch repos, so this normally installs from EGO
    install_extension "Dash to Dock" "dash-to-dock@micxgx.gmail.com" \
        "gnome-shell-extension-dash-to-dock" 307
}

install_dash_to_panel() {
    log_step "Setting up Dash to Panel (Windows-style)..."
    install_extension "Dash to Panel" "dash-to-panel@jderose9.github.com" \
        "gnome-shell-extension-dash-to-panel" 1160
}

# ============================================================================
# Configuration
# ============================================================================

configure_dock_style() {
    log_step "Configuring Dock (macOS) style..."

    # Disable Dash to Panel if enabled
    disable_extension dash-to-panel@jderose9.github.com

    # Enable Dash to Dock
    enable_extension dash-to-dock@micxgx.gmail.com

    # Configure Dash to Dock settings
    dconf write /org/gnome/shell/extensions/dash-to-dock/dock-position "'BOTTOM'"
    dconf write /org/gnome/shell/extensions/dash-to-dock/dock-fixed true
    dconf write /org/gnome/shell/extensions/dash-to-dock/autohide false
    dconf write /org/gnome/shell/extensions/dash-to-dock/intellihide false
    dconf write /org/gnome/shell/extensions/dash-to-dock/extend-height false
    dconf write /org/gnome/shell/extensions/dash-to-dock/dash-max-icon-size 48
    dconf write /org/gnome/shell/extensions/dash-to-dock/background-opacity 0.7
    dconf write /org/gnome/shell/extensions/dash-to-dock/transparency-mode "'DYNAMIC'"
    dconf write /org/gnome/shell/extensions/dash-to-dock/custom-theme-shrink true
    dconf write /org/gnome/shell/extensions/dash-to-dock/show-trash true
    dconf write /org/gnome/shell/extensions/dash-to-dock/show-mounts false
    dconf write /org/gnome/shell/extensions/dash-to-dock/running-indicator-style "'DOTS'"

    # JesterNet colors
    dconf write /org/gnome/shell/extensions/dash-to-dock/custom-background-color true
    dconf write /org/gnome/shell/extensions/dash-to-dock/background-color "'rgba(10, 10, 20, 0.7)'"

    log_success "Dock style configured"
}

configure_taskbar_style() {
    log_step "Configuring Taskbar (Windows) style..."

    # Disable Dash to Dock if enabled
    disable_extension dash-to-dock@micxgx.gmail.com

    # Enable Dash to Panel
    enable_extension dash-to-panel@jderose9.github.com

    # Configure Dash to Panel settings
    dconf write /org/gnome/shell/extensions/dash-to-panel/panel-positions '{"0":"BOTTOM"}'
    dconf write /org/gnome/shell/extensions/dash-to-panel/panel-sizes '{"0":42}'
    dconf write /org/gnome/shell/extensions/dash-to-panel/panel-element-positions '{"0":[{"element":"showAppsButton","visible":true,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}]}'

    # Appearance
    dconf write /org/gnome/shell/extensions/dash-to-panel/trans-use-custom-bg true
    dconf write /org/gnome/shell/extensions/dash-to-panel/trans-bg-color "'#0a0a14'"
    dconf write /org/gnome/shell/extensions/dash-to-panel/trans-use-custom-opacity true
    dconf write /org/gnome/shell/extensions/dash-to-panel/trans-panel-opacity 0.7

    # Taskbar behavior
    dconf write /org/gnome/shell/extensions/dash-to-panel/group-apps true
    dconf write /org/gnome/shell/extensions/dash-to-panel/group-apps-label-font-size 12
    dconf write /org/gnome/shell/extensions/dash-to-panel/group-apps-use-launchers false
    dconf write /org/gnome/shell/extensions/dash-to-panel/isolate-workspaces true

    # App button (like Start menu)
    dconf write /org/gnome/shell/extensions/dash-to-panel/show-apps-icon-file "'/usr/share/icons/hicolor/scalable/apps/start-here.svg'"
    dconf write /org/gnome/shell/extensions/dash-to-panel/animate-appicon-hover true

    # Running indicators
    dconf write /org/gnome/shell/extensions/dash-to-panel/dot-style-focused "'DASHES'"
    dconf write /org/gnome/shell/extensions/dash-to-panel/dot-style-unfocused "'DOTS'"
    dconf write /org/gnome/shell/extensions/dash-to-panel/dot-color-override true
    dconf write /org/gnome/shell/extensions/dash-to-panel/dot-color-1 "'#00ffff'"
    dconf write /org/gnome/shell/extensions/dash-to-panel/dot-color-2 "'#ff00ff'"

    log_success "Taskbar style configured"
}

# ============================================================================
# Main Selection Menu
# ============================================================================

show_selection_menu() {
    clear
    print_header

    echo -e "${CYAN}Choose your desktop style:${NC}"
    echo ""
    echo -e "  ${GREEN}[D]${NC} Dock Bar ${CYAN}(macOS-style)${NC}"
    echo "      - Centered dock at bottom"
    echo "      - Auto-hide when windows overlap"
    echo "      - Clean, minimal top bar"
    echo "      - Best for: macOS users, aesthetic lovers"
    echo ""
    print_dock_preview
    echo ""
    echo -e "  ${BLUE}[W]${NC} Windows Bar ${CYAN}(Taskbar-style)${NC}"
    echo "      - Full-width taskbar at bottom"
    echo "      - App menu (like Start button)"
    echo "      - Window list with labels"
    echo "      - Best for: Windows users, productivity focus"
    echo ""
    print_taskbar_preview
    echo ""
    echo -e "  ${YELLOW}[S]${NC} Skip - Keep current desktop style"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    local choice="$1"

    # If no argument, show interactive menu
    if [ -z "$choice" ]; then
        show_selection_menu
        read -p "  Select style [D/W/S]: " choice
    fi

    case "${choice^^}" in
        D|DOCK|MAC|MACOS)
            echo ""
            log_step "Installing Dock (macOS) style..."
            check_gnome_extensions_cli
            install_dash_to_dock
            configure_dock_style
            echo ""
            log_success "Dock style installed!"
            echo ""
            echo -e "${YELLOW}Please log out and back in for changes to take effect.${NC}"
            echo ""
            ;;

        W|WINDOWS|TASKBAR|PANEL)
            echo ""
            log_step "Installing Taskbar (Windows) style..."
            check_gnome_extensions_cli
            install_dash_to_panel
            configure_taskbar_style
            echo ""
            log_success "Taskbar style installed!"
            echo ""
            echo -e "${YELLOW}Please log out and back in for changes to take effect.${NC}"
            echo ""
            ;;

        S|SKIP)
            echo ""
            log_success "Keeping current desktop style"
            echo ""
            ;;

        *)
            log_error "Invalid choice: $choice"
            echo "Usage: $0 [dock|windows|skip]"
            exit 1
            ;;
    esac
}

# Run
main "$1"
