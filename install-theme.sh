#!/bin/bash
# ============================================================================
# JesterNet DarkGlass Theme Installer
# ============================================================================
# Installs the full DarkGlass glassmorphic theme on a running GNOME system
# Run from the jesternet-os directory after first login
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_step()    { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error()   { echo -e "${RED}✗${NC} $1"; }

print_header() {
    echo -e "${MAGENTA}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║            JesterNet DarkGlass Theme Installer                   ║
║         Glassmorphic Cyberpunk Desktop for GNOME                 ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ============================================================================
# Checks
# ============================================================================

check_gnome() {
    if ! command -v gnome-shell &> /dev/null; then
        log_error "GNOME Shell not found. This theme requires GNOME."
        exit 1
    fi
    log_success "GNOME detected"
}

check_script_dir() {
    if [ ! -d "$SCRIPT_DIR/extensions" ]; then
        log_error "Extensions directory not found. Run this script from the jesternet-os folder."
        exit 1
    fi
    log_success "Theme files found at: $SCRIPT_DIR"
}

# ============================================================================
# AUR Helper
# ============================================================================

ensure_yay() {
    if command -v yay &> /dev/null; then
        log_success "yay already installed"
        return
    fi

    log_step "Installing yay (AUR helper)..."
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd "$SCRIPT_DIR"
    rm -rf /tmp/yay
    log_success "yay installed"
}

# ============================================================================
# Packages
# ============================================================================

install_packages() {
    log_step "Installing required packages..."

    # pacman packages
    sudo pacman -S --needed --noconfirm \
        gnome-tweaks \
        gnome-shell-extensions \
        dconf-editor \
        unzip \
        breeze-cursors

    log_success "Base packages installed"

    # AUR packages
    log_step "Installing AUR packages (Orchis theme + Extension Manager)..."
    yay -S --needed --noconfirm \
        orchis-theme \
        extension-manager

    log_success "AUR packages installed"
}

# ============================================================================
# Icons
# ============================================================================

install_icons() {
    log_step "Installing DarkGlass icon theme..."

    mkdir -p ~/.local/share/icons
    cp -r "$SCRIPT_DIR/icons/DarkGlass" ~/.local/share/icons/
    gtk-update-icon-cache -f -t ~/.local/share/icons/DarkGlass/ 2>/dev/null || true

    log_success "Icons installed"
}

# ============================================================================
# GTK Theme
# ============================================================================

install_gtk_theme() {
    log_step "Installing GTK theme..."

    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
    cp "$SCRIPT_DIR/gtk/gtk-3.0.css" ~/.config/gtk-3.0/gtk.css
    cp "$SCRIPT_DIR/gtk/gtk-4.0.css" ~/.config/gtk-4.0/gtk.css

    log_success "GTK theme installed"
}

# ============================================================================
# GNOME Shell Theme
# ============================================================================

install_shell_theme() {
    log_step "Installing GNOME Shell theme..."

    mkdir -p ~/.themes/DarkGlass/gnome-shell
    cp "$SCRIPT_DIR/gnome-shell/gnome-shell.css" ~/.themes/DarkGlass/gnome-shell/

    log_success "Shell theme installed"
}

# ============================================================================
# Wallpaper
# ============================================================================

install_wallpaper() {
    if [ -f "$SCRIPT_DIR/config/wallpaper.jpg" ]; then
        log_step "Installing wallpaper..."
        mkdir -p ~/.config
        cp "$SCRIPT_DIR/config/wallpaper.jpg" ~/.config/background
        log_success "Wallpaper installed"
    fi
}

# ============================================================================
# GNOME Extensions
# ============================================================================

install_extensions() {
    log_step "Installing GNOME extensions..."

    mkdir -p ~/.local/share/gnome-shell/extensions

    # Install all bundled extensions from extensions/ directory
    local count=0
    for ext_dir in "$SCRIPT_DIR/extensions"/*/; do
        local ext_name
        ext_name=$(basename "$ext_dir")
        cp -r "$ext_dir" ~/.local/share/gnome-shell/extensions/
        echo -e "  ${GREEN}✓${NC} $ext_name"
        # Not ((count++)): it returns status 1 when count is 0, which aborts under set -e
        count=$((count + 1))
    done

    # Install darkglass-themer (in root of repo)
    if [ -d "$SCRIPT_DIR/darkglass-themer@jesternet.com" ]; then
        cp -r "$SCRIPT_DIR/darkglass-themer@jesternet.com" ~/.local/share/gnome-shell/extensions/
        echo -e "  ${GREEN}✓${NC} darkglass-themer@jesternet.com"
        count=$((count + 1))
    fi

    log_success "$count extensions installed"
}

# ============================================================================
# Apply Settings
# ============================================================================

apply_gsettings() {
    log_step "Applying desktop settings..."

    # Load full interface config from file
    if [ -f "$SCRIPT_DIR/config/desktop-interface.conf" ]; then
        dconf load /org/gnome/desktop/interface/ < "$SCRIPT_DIR/config/desktop-interface.conf" 2>/dev/null || true
        log_success "Interface settings applied"
    fi

    # Wallpaper
    if [ -f ~/.config/background ]; then
        gsettings set org.gnome.desktop.background picture-uri "file://$HOME/.config/background"
        gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/.config/background"
    fi
}

apply_blur_settings() {
    log_step "Applying blur effects config..."

    if [ -f "$SCRIPT_DIR/config/blur-my-shell.conf" ]; then
        dconf load /org/gnome/shell/extensions/blur-my-shell/ < "$SCRIPT_DIR/config/blur-my-shell.conf" 2>/dev/null || true
        log_success "Blur settings applied"
    else
        log_warning "Blur config not found, skipping"
    fi
}

# Per-extension look and layout, exported from the reference machine.
# config/extensions/<name>.conf loads into /org/gnome/shell/extensions/<name>/.
apply_extension_settings() {
    log_step "Applying extension settings..."

    local conf_dir="$SCRIPT_DIR/config/extensions"
    [ -d "$conf_dir" ] || { log_warning "No extension settings found, skipping"; return 0; }

    local conf name
    for conf in "$conf_dir"/*.conf; do
        name=$(basename "$conf" .conf)
        [ "$name" = "burn-my-windows-profile" ] && continue
        dconf load "/org/gnome/shell/extensions/$name/" < "$conf"
        echo -e "  ${GREEN}✓${NC} $name"
    done

    # Burn My Windows keeps its effect choice in a profile file referenced by an
    # absolute path, so install the profile and point the setting at this $HOME.
    if [ -f "$conf_dir/burn-my-windows-profile.conf" ]; then
        local profile="$HOME/.config/burn-my-windows/profiles/jesternet.conf"
        mkdir -p "$(dirname "$profile")"
        cp "$conf_dir/burn-my-windows-profile.conf" "$profile"
        dconf write /org/gnome/shell/extensions/burn-my-windows/active-profile "'$profile'"
        echo -e "  ${GREEN}✓${NC} burn-my-windows profile"
    fi

    log_success "Extension settings applied"
}

# ============================================================================
# Enable Extensions
# ============================================================================

# `gnome-extensions enable` only works on extensions the running shell has
# already loaded. On Wayland freshly copied extensions aren't loaded until the
# next login, so add them to enabled-extensions directly; the shell picks them
# up on login.
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

enable_extensions() {
    log_step "Enabling extensions..."

    # Only the extensions the reference machine runs; the rest (e.g. ThinkPad
    # thermal) are bundled for users who want them but left off by default.
    local list="$SCRIPT_DIR/config/enabled-extensions.txt"
    local uuids=()
    if [ -f "$list" ]; then
        mapfile -t uuids < <(grep -vE '^\s*(#|$)' "$list")
    else
        local ext_dir
        for ext_dir in "$SCRIPT_DIR/extensions"/*/; do
            uuids+=("$(basename "$ext_dir")")
        done
    fi

    local enabled=0 uuid
    for uuid in "${uuids[@]}"; do
        if [ ! -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]; then
            log_warning "$uuid listed but not installed, skipping"
            continue
        fi
        enable_extension "$uuid"
        echo -e "  ${GREEN}✓${NC} $uuid"
        enabled=$((enabled + 1))
    done

    # Apply shell theme via user-theme extension
    dconf write /org/gnome/shell/extensions/user-theme/name "'DarkGlass'" 2>/dev/null || true

    log_success "$enabled extensions enabled (active after next login)"
}

# ============================================================================
# Summary
# ============================================================================

print_summary() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}            DarkGlass Theme Installation Complete!${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${CYAN}What was installed:${NC}"
    echo "    Icons:      DarkGlass icon theme"
    echo "    GTK:        DarkGlass GTK 3.0 + 4.0 theme"
    echo "    Shell:      DarkGlass GNOME Shell theme"
    echo "    Extensions: All bundled extensions"
    echo "    Blur:       Glassmorphic blur effects"
    echo ""
    echo -e "  ${YELLOW}Next steps:${NC}"
    echo "    1. Log out and back in to activate all extensions"
    echo "    2. Open Extension Manager to manage individual extensions"
    echo "    3. Use GNOME Tweaks to fine-tune fonts and behaviour"
    echo "    4. Click the colour wheel icon in the top bar to customise DarkGlass"
    echo ""
    echo -e "  ${CYAN}Tip:${NC} Run ${GREEN}./desktop-style.sh${NC} to choose Dock or Taskbar layout"
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

print_header
check_gnome
check_script_dir

echo ""
read -p "This will install the full DarkGlass theme. Continue? [Y/n] " confirm
if [[ "${confirm,,}" == "n" ]]; then
    echo "Cancelled."
    exit 0
fi
echo ""

ensure_yay
install_packages
install_icons
install_gtk_theme
install_shell_theme
install_wallpaper
install_extensions
apply_gsettings
apply_blur_settings
apply_extension_settings
enable_extensions
print_summary
