# JesterNet OS

```
       ▄▄▄██▀▀▀▓█████   ██████ ▄▄▄█████▓▓█████  ██▀███   ███▄    █ ▓█████▄▄▄█████▓
         ▒██   ▓█   ▀ ▒██    ▒ ▓  ██▒ ▓▒▓█   ▀ ▓██ ▒ ██▒ ██ ▀█   █ ▓█   ▀▓  ██▒ ▓▒
         ░██   ▒███   ░ ▓██▄   ▒ ▓██░ ▒░▒███   ▓██ ░▄█ ▒▓██  ▀█ ██▒▒███  ▒ ▓██░ ▒░
      ▓██▄██▓  ▒▓█  ▄   ▒   ██▒░ ▓██▓ ░ ▒▓█  ▄ ▒██▀▀█▄  ▓██▒  ▐▌██▒▒▓█  ▄░ ▓██▓ ░
       ▓███▒   ░▒████▒▒██████▒▒  ▒██▒ ░ ░▒████▒░██▓ ▒██▒▒██░   ▓██░░▒████▒ ▒██▒ ░
       ▒▓▒▒░   ░░ ▒░ ░▒ ▒▓▒ ▒ ░  ▒ ░░   ░░ ▒░ ░░ ▒▓ ░▒▓░░ ▒░   ▒ ▒ ░░ ▒░ ░ ▒ ░░
```

**A Futuristic Glassmorphic Desktop for Arch Linux**

Welcome to JesterNet OS - a complete desktop transformation for users migrating from Windows or macOS to Arch Linux. This package includes a stunning glassmorphic theme, pre-configured desktop layouts, and one-click installers for development environments.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Desktop Styles](#desktop-styles)
- [Theme Components](#theme-components)
- [Development Stacks](#development-stacks)
- [System Baseline](#system-baseline)
- [For Windows Users](#for-windows-users)
- [For macOS Users](#for-macos-users)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)

---

## Features

### Glassmorphic Theme
- Frosted glass transparency effects
- Cyan/Magenta cyberpunk color palette
- Custom icons for 40+ applications
- Programming language file-type icons (23 SVG icons)
- GTK3/GTK4 theme integration

### Desktop Layouts
Choose your preferred workflow:

| Style | Description | Best For |
|-------|-------------|----------|
| **Dock Bar** (macOS-style) | Bottom dock with app icons, no taskbar | Users from macOS, clean aesthetic lovers |
| **Start Bar** (Windows-style) | Bottom taskbar with app menu, system tray | Users from Windows, traditional workflow |

### Development Stacks
One-click installation for complete development environments:
- **Tauri** - Rust + Svelte/React desktop apps
- **Android** - Full Android SDK/NDK setup
- **Go** - Go with LSP, linters, and tools
- **Python** - Poetry, Ruff, Pyright
- **Zig** - Zig with ZLS
- **Web** - Node, Bun, Vite, Tailwind

### Productivity Suites
- **Office + Multimedia** - LibreOffice, GIMP, Inkscape, VLC
- **Content Creator** - OBS Studio, Kdenlive, Audacity

---

## Requirements

- **Arch Linux** (or Arch-based: EndeavourOS, Manjaro)
- **GNOME Desktop** (45–49)
- **4GB+ RAM** minimum (8GB recommended for development stacks)
- **Internet connection** for package downloads

### Bundled GNOME Extensions
The theme installer (`install-theme.sh`) automatically installs and enables all 19 bundled extensions including:
- **Blur My Shell** — glassmorphic blur effects
- **Dash to Dock** — macOS-style dock (Dock layout)
- **Dash to Panel** — Windows-style taskbar (Start Bar layout)
- **User Themes** — custom shell theme support
- **Burn My Windows** — animated window close effects
- **Tiling Shell** — window tiling/snapping
- **Vitals** — system monitor in top bar
- **Claude Shepherd** — monitor Claude Code instances from the desktop
- **DarkGlass Themer** — live theme editor (colour wheel in top bar)

---

## Quick Start

Boot from the Arch Linux ISO (via Ventoy USB or direct), then:

### 1. Connect to WiFi

```bash
iwctl
station wlan0 connect "Your-SSID"
# enter password when prompted
exit
```

### 2. Verify internet

```bash
ping -c 3 8.8.8.8
```

### 3. Install git and clone

```bash
pacman -Sy git
git clone https://github.com/quantum-encoding/jesternet-os.git
cd jesternet-os
bash install.sh
```

### 4. Follow the prompts

The installer will ask you to:
- Select your target disk (supports NVMe, SATA, eMMC, and all disk types)
- Set hostname, username, and password
- Choose desktop style: **[D] Dock Bar** (macOS-style) or **[W] Windows Bar** (taskbar-style)
- Optionally install development stacks

### 5. Reboot

Remove the USB and reboot. Log in and run:

```bash
cd jesternet-os
bash install-theme.sh
```

### Alternative: Install from Ventoy USB

If you have the repo files on your Ventoy drive:

```bash
iwctl
station wlan0 connect "Your-SSID"
exit

mkdir -p /mnt/ventoy
mount /dev/mapper/sdb1 /mnt/ventoy
bash /mnt/ventoy/jesternet-os/install.sh
```

> **Note:** If the Ventoy mount path differs, run `lsblk` to find the correct device.

---

## Desktop Styles

### Dock Bar (macOS Style)

```
┌─────────────────────────────────────────────────────────────────┐
│  Activities                              🔊 🔋 📶  Mon 12:00    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                                                                 │
│                        Your Desktop                             │
│                                                                 │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│         🦊  📁  💻  🎵  ⚙️   |   📌 Running Apps   |   🗑️       │
│                         ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔                       │
└─────────────────────────────────────────────────────────────────┘
```

**Features:**
- Centered dock at bottom
- Always visible by default (no auto-hide)
- App icons with indicators for running apps
- Trash icon on the right
- Clean, minimal top bar

**Best for:** macOS users, those who prefer a clean desktop

### Windows Bar (Taskbar Style)

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                                                                 │
│                        Your Desktop                             │
│                                                                 │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ ⬡ Apps │ 🦊 Firefox │ 📁 Files │ 💻 Terminal │    🔊 🔋 12:00  │
└─────────────────────────────────────────────────────────────────┘
```

**Features:**
- Full-width bottom taskbar
- App menu button (like Start menu)
- Window list showing open applications
- System tray with clock
- Familiar Windows workflow

**Best for:** Windows users, those who prefer taskbar workflow

---

## Theme Components

### DarkGlass Theme

The glassmorphic theme includes:

| Component | Description |
|-----------|-------------|
| **Icons** | 40+ custom app icons + 23 file-type icons |
| **GTK Theme** | Frosted glass window decorations |
| **Shell Theme** | Transparent top bar and overview |
| **Blur Effects** | Real-time blur behind windows |

### Color Palette

```
Primary:    #00FFFF (Cyan)
Accent:     #FF00FF (Magenta)
Background: #0a0a0f (Deep Black)
Glass:      rgba(20, 20, 30, 0.7)
```

### Included Icons

**Applications:**
Firefox, Brave, VS Code, Ghostty, OBS Studio, Steam, Inkscape,
GIMP, Calculator, Calendar, System Monitor, and 30+ more

**File Types:**
Python, Rust, Go, Zig, TypeScript, JavaScript, C, C++, C#,
Swift, Julia, Mojo, Docker, YAML, JSON, Markdown, and more

---

## Development Stacks

### Tauri Stack
Build cross-platform desktop apps with web technologies.

```bash
./install.sh tauri
```

**Installs:**
- Rust + Cargo
- Node.js + pnpm + Bun
- Tauri CLI
- WebKit/GTK dependencies

**Quick Start:**
```bash
new-tauri-app my-app          # Creates Svelte + Tauri app
new-tauri-app my-app react    # Creates React + Tauri app
cd my-app && pnpm tauri dev
```

### Android Stack
Full Android development environment.

```bash
./install.sh android
```

**Installs:**
- Java JDK 17
- Android SDK + NDK
- Kotlin + Gradle
- ADB + Fastboot
- Emulator

**Quick Start:**
```bash
adb devices                   # List connected devices
avdmanager create avd ...     # Create emulator
```

### Go Stack
Modern Go development setup.

```bash
./install.sh go
```

**Installs:**
- Go (latest)
- gopls (language server)
- delve (debugger)
- golangci-lint
- air (live reload)

**Quick Start:**
```bash
new-go-project my-app         # Creates Go CLI app
new-go-project my-api api     # Creates Go API server
cd my-app && task run
```

### Python Stack
Python with modern tooling.

```bash
./install.sh python
```

**Installs:**
- Python 3 + pip + pipx
- Poetry (dependency management)
- Ruff (fast linter/formatter)
- Pyright (type checker)
- pyenv (version management)

**Quick Start:**
```bash
new-python-project my-app
cd my-app && poetry shell
```

### Web Frontend Stack
Modern frontend development.

```bash
./install.sh web
```

**Installs:**
- Node.js + npm
- Bun (fast runtime)
- pnpm (fast package manager)
- Vite, TypeScript, ESLint, Prettier
- Tailwind CSS CLI

**Quick Start:**
```bash
new-svelte-app my-app         # SvelteKit + Tailwind
new-react-app my-app          # React + Vite + Tailwind
new-vue-app my-app            # Vue + Vite + Tailwind
```

---

## System Baseline

JesterNet OS ships on the Linux 7.0 kernel series, which brings substantial changes — Rust drivers stable, AccECN networking, XFS self-healing, BPF-filtered io_uring, SHA-512 module signing, and improved swap performance among them. To make these gains measurable rather than vibes-based, the package includes a portable baseline tool.

### Run a baseline

```bash
cd ~/JesterNet
./linux-baseline.sh                  # writes baseline-<host>-<UTC>.txt to PWD
./linux-baseline.sh ~/baselines      # custom output dir
```

Total runtime is roughly 90 seconds. The script needs no extra packages — it works against a stock Linux install using `bash`, `coreutils`, and `openssl`. If `sysbench`, `fio`, `ethtool`, or `dmidecode` are present, it uses them automatically for richer numbers.

### What it captures

| Section | Contents |
|---|---|
| System identity | Hostname, distro, kernel, uname, DMI vendor/product, boot mode, distro kernel package |
| Kernel & boot | Kernel command line, preempt model, taint flags, `systemd-analyze` boot time |
| CPU | `lscpu` dump, governor, scaling driver, `intel_pstate` status, EPP, microcode, all `vulnerabilities/*` mitigation flags |
| Memory | Total / swap / hugepages, swappiness, THP mode, zswap configuration |
| Storage | `lsblk`, mount table (with pseudo-FS filtered out) |
| Network | `ip` link/addr, default gateway, per-interface ethtool speed and driver |
| **Linux 7.0 probes** | `CONFIG_RUST`, `CONFIG_RUSTC_VERSION_TEXT`, `CONFIG_BPF_LSM`, `CONFIG_IO_URING`, `CONFIG_MODULE_SIG_HASH`, `CONFIG_XFS_ONLINE_SCRUB`, `CONFIG_XFS_DRAIN_INTENTS`, `CONFIG_XFS_LIVE_HOOKS`, all four `tcp_ecn*` AccECN sysctls, `kernel.io_uring_disabled`, count of loaded Rust modules |
| Power & frequency | Per-core current frequency min/max/avg, AC vs battery |
| Benchmarks | OpenSSL AES-256-GCM single + multi-thread, OpenSSL SHA-256, `dd` memcpy bandwidth proxy, `dd` direct-IO sequential disk write & read; optional `sysbench cpu/memory` and `fio randread 4k` if installed |
| Run info | Total duration, tools detected, user, root flag |

### Output format

Every fact is written as a `key=value` line under markdown section headers, so two reports diff cleanly with `diff -u`:

```bash
diff -u ~/baselines/baseline-host-A.txt ~/baselines/baseline-host-B.txt | less
```

This is the recommended workflow:

1. Run baseline immediately after first boot — captures the stock JesterNet 7.0 numbers.
2. Run again after any meaningful change (kernel upgrade, governor switch, BIOS update, mitigations toggle).
3. Diff to attribute the change.

### Tunable knobs

```bash
BASELINE_DD_MB=4096       ./linux-baseline.sh   # bigger disk bench (default 1024)
BASELINE_CPU_SECONDS=10   ./linux-baseline.sh   # longer openssl runs (default 5)
BASELINE_MEM_GB=16        ./linux-baseline.sh   # bigger memcpy proxy (default 8)
BASELINE_BENCH_DIR=/mnt/data ./linux-baseline.sh   # bench a specific drive
```

The script auto-skips tmpfs for disk benchmarks — `/tmp` on Arch is RAM-backed and would produce meaningless 47 GB/s "disk" numbers. The bench directory is auto-picked from `$PWD`, `$HOME`, then `/var/tmp`, choosing the first writable non-tmpfs location. Override with `BASELINE_BENCH_DIR` to test a specific block device.

### Caveats worth reading before comparing

- **CPU governor** swings benches 20–40%. Captured under `cpu_governor` — confirm both runs used the same value before blaming hardware.
- **Mitigations matter.** `mitigations=off` in the kernel cmdline can shift CPU numbers significantly. The script captures every flag under `/sys/devices/system/cpu/vulnerabilities/`.
- **Direct-IO read** is the disk number you want. If the filesystem rejects O_DIRECT (some btrfs configs), the script falls back to a cached read and labels the section accordingly.
- **`loaded_rust_modules=0` is normal.** `CONFIG_RUST=y` means the kernel can load Rust modules; the upstream Rust drivers in 7.0 are still narrow, so few systems have one bound at runtime.
- **Pre-7.0 detection.** On older kernels, the four `sysctl_net_ipv4_tcp_ecn_option*` keys read `MISSING` — the cleanest single-glance test of "is this kernel 7.0 or older."

---

## For Windows Users

Welcome to Linux! Here's what you need to know:

### Familiar Concepts

| Windows | Linux Equivalent |
|---------|-----------------|
| C:\\ drive | `/` (root) |
| C:\\Users\\You | `/home/you` or `~` |
| Program Files | `/usr/bin` or installed via `pacman` |
| Control Panel | Settings app or `gnome-control-center` |
| Task Manager | System Monitor or `htop` |
| CMD/PowerShell | Terminal (Ghostty, Konsole) |
| .exe files | No extension needed, or AppImages |
| Windows Update | `sudo pacman -Syu` |

### Installing Software

Forget downloading .exe files! Use the package manager:

```bash
# Search for software
pacman -Ss firefox

# Install software
sudo pacman -S firefox

# Update everything
sudo pacman -Syu

# Remove software
sudo pacman -R firefox
```

### Keyboard Shortcuts

| Action | Windows | JesterNet |
|--------|---------|-----------|
| Open terminal | - | `Super + T` or click icon |
| Show all apps | `Win` | `Super` (tap) |
| Switch windows | `Alt + Tab` | `Alt + Tab` |
| Close window | `Alt + F4` | `Alt + F4` |
| File manager | `Win + E` | `Super + E` or click icon |
| Lock screen | `Win + L` | `Super + L` |

### Recommended: Windows-Style Taskbar

If you're coming from Windows, choose the **Windows Bar** style during setup. It gives you:
- Familiar taskbar at the bottom
- App menu like the Start button
- System tray with clock
- Window buttons for each open app

---

## For macOS Users

The default **Dock Bar** style will feel familiar:

### Familiar Concepts

| macOS | Linux Equivalent |
|-------|-----------------|
| Finder | Files (Nautilus) |
| Spotlight | `Super` key to search |
| Terminal | Ghostty/Konsole |
| Homebrew | `pacman` |
| .app bundles | Native packages or Flatpaks |
| System Preferences | Settings |

### The Dock

Just like macOS:
- Click icons to launch apps
- Running apps show indicator dots
- Drag to reorder
- Right-click for options

---

## Customization

### Changing Desktop Style Later

Already installed but want to switch styles?

**Switch to Dock (macOS) style:**
```bash
gnome-extensions disable dash-to-panel@jderose9.github.com
gnome-extensions enable dash-to-dock@micxgx.gmail.com
```

**Switch to Taskbar (Windows) style:**
```bash
gnome-extensions disable dash-to-dock@micxgx.gmail.com
gnome-extensions enable dash-to-panel@jderose9.github.com
```

### Adjusting Transparency

Use the DarkGlass Theme Editor extension (color wheel in top bar) to adjust:
- Blur intensity
- Window transparency
- Glass brightness

### Adding More Icons

Place custom icons in:
```
~/.local/share/icons/DarkGlass/apps/scalable/
```

Then refresh:
```bash
gtk-update-icon-cache -f ~/.local/share/icons/DarkGlass/
```

---

## Troubleshooting

### Theme Not Applying

1. Make sure GNOME Extensions are enabled:
   ```bash
   gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com
   ```

2. Log out and back in

3. Use GNOME Tweaks to select the theme manually

### Blur Not Working

Install and enable Blur My Shell:
```bash
# From extensions.gnome.org or:
gnome-extensions enable blur-my-shell@aunetx
```

### Icons Not Showing

Rebuild the icon cache:
```bash
gtk-update-icon-cache -f -t ~/.local/share/icons/DarkGlass/
```

### Dock/Taskbar Not Appearing

Make sure the correct extension is enabled:
```bash
# For Dock style:
gnome-extensions enable dash-to-dock@micxgx.gmail.com

# For Windows style:
gnome-extensions enable dash-to-panel@jderose9.github.com
```

### Downloads Are Slow

The installers use aria2 with 16 connections. If downloads fail:
```bash
# Check aria2 is installed
which aria2c

# If not, install it
sudo pacman -S aria2
```

---

## File Structure

```
jesternet-os/
├── install.sh                # Arch Linux installer (from live ISO)
├── install-theme.sh          # DarkGlass theme installer (run after first login)
├── desktop-style.sh          # Switch between Dock/Taskbar layouts
├── jesternet-setup.sh        # Interactive setup menu
├── optimize-icons.sh         # Compress PNG icons
│
├── arch-install/             # Enterprise/advanced Arch install configs
│
├── config/                   # GNOME/Extension configs
│   ├── blur-my-shell.conf
│   ├── desktop-interface.conf
│   └── wallpaper.jpg
│
├── extensions/               # 19 bundled GNOME extensions
│   ├── blur-my-shell@aunetx/
│   ├── claude-shepherd@quantum-forge/
│   ├── burn-my-windows@schneegans.github.com/
│   ├── tilingshell@ferrarodomenico.com/
│   ├── Vitals@CoreCoding.com/
│   └── ...
│
├── darkglass-themer@jesternet.com/  # Live theme editor extension
│
├── dev-stacks/               # Development environment installers
│   ├── common.sh             # Shared functions (aria2 setup)
│   ├── tauri-stack.sh
│   ├── android-stack.sh
│   ├── go-stack.sh
│   ├── python-stack.sh
│   ├── zig-stack.sh
│   ├── web-stack.sh
│   ├── office-multimedia.sh
│   └── content-creator.sh
│
├── icons/DarkGlass/          # Icon theme
│   ├── apps/                 # Application icons
│   ├── mimetypes/            # File type icons
│   └── places/               # Folder icons
│
├── gtk/                      # GTK theme CSS
├── gnome-shell/              # Shell theme CSS
└── aur-package/              # AUR PKGBUILD for distribution
```

---

## Credits

Created for the Arch Linux community.

**The Doctrine of Sovereign Artifacts is fulfilled.**

---

## License

MIT License - Free to use, modify, and distribute.

---

## Support

- Issues: [GitHub Issues](https://github.com/quantum-encoding/jesternet-os/issues)
- Discussions: [GitHub Discussions](https://github.com/quantum-encoding/jesternet-os/discussions)

---

```
    "The future is already here — it's just not evenly distributed."
                                                    - William Gibson
```
