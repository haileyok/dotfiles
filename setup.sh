#!/usr/bin/env bash
#
# setup.sh — Symlink dotfiles, clone external dependencies, and guide
# shell setup. Safe to re-run; existing symlinks are replaced.
#
# Prerequisites:
#   - nix with flakes enabled
#   - Run from the dotfiles directory (or set DOTFILES_DIR)
#
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONFIG_DIR="${HOME}/.config"

echo "=== Dotfiles setup ==="
echo "Source:  $DOTFILES_DIR"
echo "Config:  $CONFIG_DIR"
echo

# ---------------------------------------------------------------------------
# 1. Symlinks
# ---------------------------------------------------------------------------
echo "--- Creating symlinks ---"

link_file() {
    local src="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -e "$dst" ]; then
        echo "  WARNING: $dst exists and is not a symlink — backing up to ${dst}.bak"
        mv "$dst" "${dst}.bak"
    fi
    ln -s "$src" "$dst"
    echo "  ✓ $dst -> $src"
}

# Home-level files
link_file "$DOTFILES_DIR/.zshrc"        "$HOME/.zshrc"
link_file "$DOTFILES_DIR/.bashrc"       "$HOME/.bashrc"
link_file "$DOTFILES_DIR/.tmux.conf"    "$HOME/.tmux.conf"

# XDG config files
link_file "$DOTFILES_DIR/starship.toml"  "$CONFIG_DIR/starship.toml"
link_file "$DOTFILES_DIR/ghostty"        "$CONFIG_DIR/ghostty"
link_file "$DOTFILES_DIR/nvim"           "$CONFIG_DIR/nvim"
link_file "$DOTFILES_DIR/sway"           "$CONFIG_DIR/sway"
link_file "$DOTFILES_DIR/waybar"         "$CONFIG_DIR/waybar"
link_file "$DOTFILES_DIR/swaync"         "$CONFIG_DIR/swaync"
link_file "$DOTFILES_DIR/swayidle"       "$CONFIG_DIR/swayidle"
link_file "$DOTFILES_DIR/swaylock"       "$CONFIG_DIR/swaylock"
link_file "$DOTFILES_DIR/zellij"         "$CONFIG_DIR/zellij"
link_file "$DOTFILES_DIR/gtk-3.0"        "$CONFIG_DIR/gtk-3.0"
link_file "$DOTFILES_DIR/gtk-4.0"        "$CONFIG_DIR/gtk-4.0"

echo

# ---------------------------------------------------------------------------
# 2. tmux plugin manager (tpm)
# ---------------------------------------------------------------------------
echo "--- Setting up tmux plugin manager (tpm) ---"
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ -d "$TPM_DIR/.git" ]; then
    echo "  ✓ tpm already cloned"
else
    git clone --depth=1 https://github.com/tmux-plugins/tpm.git "$TPM_DIR"
    echo "  ✓ tpm cloned"
fi
echo "  (Press prefix + I inside tmux to install plugins)"
echo

# ---------------------------------------------------------------------------
# 3. rofi launcher theme (adi1090x/rofi type-2)
# ---------------------------------------------------------------------------
echo "--- Setting up rofi launcher theme ---"
ROFI_LAUNCHER="$CONFIG_DIR/rofi/launchers/type-2/launcher.sh"
if [ -f "$ROFI_LAUNCHER" ]; then
    echo "  ✓ rofi type-2 launcher already installed"
else
    tmpdir="$(mktemp -d)"
    git clone --depth=1 https://github.com/adi1090x/rofi.git "$tmpdir/rofi"
    mkdir -p "$CONFIG_DIR/rofi/launchers"
    cp -r "$tmpdir/rofi/files/launchers/type-2" "$CONFIG_DIR/rofi/launchers/type-2"
    cp -r "$tmpdir/rofi/files/colors" "$CONFIG_DIR/rofi/colors" 2>/dev/null || true
    cp -r "$tmpdir/rofi/files/images" "$CONFIG_DIR/rofi/images" 2>/dev/null || true
    rm -rf "$tmpdir"

    # Patch launcher script to export LOCALE_ARCHIVE and NIXOS_OZONE_WL
    # for nix glibc locale fix and native Wayland for Electron apps
    cat > "$ROFI_LAUNCHER" << 'LAUNCHER'
#!/usr/bin/env bash

dir="$HOME/.config/rofi/launchers/type-2"
theme='style-1'

export LOCALE_ARCHIVE="$HOME/.nix-profile/lib/locale/locale-archive"
export NIXOS_OZONE_WL=1
rofi \
    -show drun \
    -theme ${dir}/${theme}.rasi
LAUNCHER
    chmod +x "$ROFI_LAUNCHER"
    echo "  ✓ rofi type-2 launcher installed (with nix locale + Wayland fixes)"
fi
echo

# ---------------------------------------------------------------------------
# 3b. Patch desktop files for nixGL (ghostty) and locale
# ---------------------------------------------------------------------------
echo "--- Patching desktop files for nix compatibility ---"
APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"

# Copy nix desktop files to user-local dir (writable, takes precedence via XDG_DATA_HOME)
for f in "$HOME"/.nix-profile/share/applications/*.desktop; do
    [ -f "$f" ] && cp "$f" "$APPS_DIR/" 2>/dev/null
done

# Patch ghostty to launch via nixGL (OpenGL bridge to system Mesa drivers)
GHOSTTY_DESKTOP="$APPS_DIR/com.mitchellh.ghostty.desktop"
if [ -f "$GHOSTTY_DESKTOP" ]; then
    sed -i 's|^Exec=.*ghostty.*|Exec=nixGL '"$HOME"'/.nix-profile/bin/ghostty --gtk-single-instance=true|' "$GHOSTTY_DESKTOP"
    sed -i 's|^TryExec=.*|TryExec=nixGL|' "$GHOSTTY_DESKTOP"
    sed -i 's|^DBusActivatable=.*|DBusActivatable=false|' "$GHOSTTY_DESKTOP"
    echo "  ✓ ghostty desktop patched (nixGL wrapper)"
fi

# Patch slack to launch via nixGL (Electron GPU compositing needs system Mesa)
SLACK_DESKTOP="$APPS_DIR/slack.desktop"
if [ -f "$SLACK_DESKTOP" ]; then
    sed -i 's|^Exec=/nix/store/.*/slack|Exec=nixGL /nix/store/[^/]*/slack|' "$SLACK_DESKTOP"
    # Add Wayland flags directly (NIXOS_OZONE_WL may not be in sway's env)
    sed -i 's|Exec=nixGL /nix/store/[^/]*/slack|& --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer --enable-wayland-ime=true|' "$SLACK_DESKTOP"
    echo "  ✓ slack desktop patched (nixGL wrapper + Wayland flags)"
fi

# Patch chromium to launch via nixGL (GPU compositing needs system Mesa)
CHROMIUM_DESKTOP="$APPS_DIR/chromium-browser.desktop"
if [ -f "$CHROMIUM_DESKTOP" ]; then
    sed -i 's|^Exec=chromium|Exec=nixGL chromium|g' "$CHROMIUM_DESKTOP"
    echo "  ✓ chromium desktop patched (nixGL wrapper)"
fi

# Patch 1password to launch via nixGL (Electron GPU compositing needs system Mesa)
ONEPASSWORD_DESKTOP="$APPS_DIR/1password.desktop"
if [ -f "$ONEPASSWORD_DESKTOP" ]; then
    sed -i 's|^Exec=1password|Exec=nixGL 1password|g' "$ONEPASSWORD_DESKTOP"
    echo "  ✓ 1password desktop patched (nixGL wrapper)"
fi

# Patch discord to launch via nixGL (Electron GPU compositing needs system Mesa)
DISCORD_DESKTOP="$APPS_DIR/discord.desktop"
if [ -f "$DISCORD_DESKTOP" ]; then
    sed -i 's|^Exec=Discord|Exec=nixGL Discord|g' "$DISCORD_DESKTOP"
    echo "  ✓ discord desktop patched (nixGL wrapper)"
fi

# Patch spotify to launch via nixGL (GPU compositing needs system Mesa)
SPOTIFY_DESKTOP="$APPS_DIR/spotify.desktop"
if [ -f "$SPOTIFY_DESKTOP" ]; then
    sed -i 's|^Exec=spotify|Exec=nixGL spotify|g' "$SPOTIFY_DESKTOP"
    echo "  ✓ spotify desktop patched (nixGL wrapper)"
fi

# Patch signal to launch via nixGL (Electron GPU compositing needs system Mesa)
SIGNAL_DESKTOP="$APPS_DIR/signal.desktop"
if [ -f "$SIGNAL_DESKTOP" ]; then
    sed -i 's|^Exec=signal-desktop|Exec=nixGL signal-desktop|g' "$SIGNAL_DESKTOP"
    echo "  ✓ signal desktop patched (nixGL wrapper)"
fi

# ---------------------------------------------------------------------------
# 3c. Clean up stale environment.d (superseded by /etc/environment)
# ---------------------------------------------------------------------------
# An earlier version of this setup created ~/.config/environment.d/nix.conf
# with LOCALE_ARCHIVE=%h/... The %h specifier doesn't expand in sway's context,
# causing locale failures. /etc/environment is the correct location.
rm -f "$HOME/.config/environment.d/nix.conf" 2>/dev/null && \
    echo "  ✓ Removed stale environment.d/nix.conf" || true

echo

# ---------------------------------------------------------------------------
# 4. Wallpaper directory
# ---------------------------------------------------------------------------
echo "--- Creating wallpaper directory ---"
mkdir -p "$HOME/bgs"
echo "  ✓ ~/bgs created (add your wallpaper image here)"
echo "  (sway config references ~/dotfiles/1350497.png)"
echo

# ---------------------------------------------------------------------------
# 4b. Bin directory (scripts like power-profiles.sh)
# ---------------------------------------------------------------------------
echo "--- Bin directory ---"
# The dotfiles/bin/ scripts are referenced by .zshrc (added to PATH)
# and by waybar (custom/power-profile module). No symlinking needed —
# .zshrc adds $HOME/dotfiles/bin to PATH directly.
echo "  ✓ ~/dotfiles/bin/ on PATH (via .zshrc)"
echo "  Scripts: power-profiles.sh (requires power-profiles-daemon on laptops)"
echo

# ---------------------------------------------------------------------------
# 4c. Minimal setup (user-only machines, no root)
# ---------------------------------------------------------------------------
# On machines where you only have a user account (no sudo), use:
#   nix profile install .#minimal
# Then symlink only the CLI configs (skip desktop/Wayland configs):
#
#   ln -sf ~/dotfiles/.zshrc ~/.zshrc
#   ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf
#   ln -sf ~/dotfiles/starship.toml ~/.config/starship.toml
#   ln -sf ~/dotfiles/nvim ~/.config/nvim
#   ln -sf ~/dotfiles/zellij ~/.config/zellij
#
# Also clone tpm for tmux:
#   git clone --depth=1 https://github.com/tmux-plugins/tpm.git ~/.tmux/plugins/tpm
echo

# ---------------------------------------------------------------------------
# 4d. YubiKey OATH support (requires sudo for package installation)
# ---------------------------------------------------------------------------
echo "--- YubiKey OATH support ---"
if command -v zypper >/dev/null 2>&1; then
    if command -v rpm >/dev/null 2>&1 && rpm -q pcsc-ccid >/dev/null 2>&1; then
        echo "  ✓ pcsc-ccid is installed"
    else
        echo "  WARNING: pcsc-ccid is not installed — ykman OATH cannot connect"
        echo "  Run: sudo zypper install pcsc-ccid"
    fi

    if systemctl is-active --quiet pcscd.socket || systemctl is-active --quiet pcscd.service; then
        echo "  ✓ pcscd is running"
    else
        echo "  To enable the PC/SC service, run:"
        echo "    sudo systemctl enable --now pcscd.socket"
    fi
else
    echo "  zypper not found — install the platform's pcsc-ccid package manually"
fi
echo

# ---------------------------------------------------------------------------
# 5. Default shell
# ---------------------------------------------------------------------------
NIX_ZSH="$HOME/.nix-profile/bin/zsh"
echo "--- Default shell ---"
if [ "$SHELL" = "$NIX_ZSH" ]; then
    echo "  ✓ zsh is already the default shell"
else
    echo "  To set zsh as your default shell, run:"
    echo "    echo '$NIX_ZSH' | sudo tee -a /etc/shells"
    echo "    chsh -s '$NIX_ZSH'"
fi
echo

# ---------------------------------------------------------------------------
# 6. SELinux: label nix store and enable nix-daemon (requires sudo)
# ---------------------------------------------------------------------------
# On SELinux-enforcing systems (default on openSUSE Tumbleweed), nix store
# files get labeled default_t, which lacks entrypoint permission. This blocks
# nix-installed zsh from being used as a login shell and prevents systemd from
# reading the nix-daemon service file — both cause login failures.
echo "--- SELinux: relabel nix store (requires sudo) ---"
if command -v semanage >/dev/null 2>&1; then
    SELINUX_MODULE="$DOTFILES_DIR/selinux/nix-store-exec.te"

    # Label nix store executables as bin_t (same context as /usr/bin/*)
    sudo semanage fcontext -m -t bin_t '/nix/store/.*' 2>/dev/null \
        || sudo semanage fcontext -a -t bin_t '/nix/store/.*'
    sudo semanage fcontext -m -t bin_t '/nix/var(/.*)?' 2>/dev/null \
        || sudo semanage fcontext -a -t bin_t '/nix/var(/.*)?'
    # Socket dir needs var_run_t so systemd can create/unlink the socket
    sudo semanage fcontext -m -t var_run_t '/nix/var/nix/daemon-socket(/.*)?' 2>/dev/null \
        || sudo semanage fcontext -a -t var_run_t '/nix/var/nix/daemon-socket(/.*)?'

    sudo restorecon -R /nix/store /nix/var 2>/dev/null
    echo "  ✓ nix store relabeled (bin_t, daemon-socket var_run_t)"

    # Install the SELinux module for entrypoint/execute permissions
    if [ -f "$SELINUX_MODULE" ] && command -v checkmodule >/dev/null 2>&1; then
        MODULE_TMP="$(mktemp -d)"
        checkmodule -M -m -o "$MODULE_TMP/nix-store-exec.mod" "$SELINUX_MODULE"
        semodule_package -o "$MODULE_TMP/nix-store-exec.pp" -m "$MODULE_TMP/nix-store-exec.mod"
        sudo semodule -i "$MODULE_TMP/nix-store-exec.pp"
        rm -rf "$MODULE_TMP"
        echo "  ✓ SELinux module nix-store-exec installed"
    else
        echo "  WARNING: checkmodule not found or .te file missing — skipping module install"
        echo "  Install with: sudo zypper install checkpolicy policycoreutils"
    fi

    # Enable and start nix-daemon (socket activation)
    sudo systemctl enable --now nix-daemon.socket 2>/dev/null || true
    sudo systemctl enable --now nix-daemon.service 2>/dev/null || true
    echo "  ✓ nix-daemon enabled"
else
    echo "  SELinux tools not found — skipping (not needed on non-SELinux systems)"
fi
echo

echo "=== Setup complete! ==="
echo
echo "Next steps:"
echo "  1. Install packages:  nix profile install .#default"
echo "  2. Set default shell: (see instructions above if not done)"
echo "  3. Add wallpaper:     cp your-wallpaper.png ~/bgs/carcig.png"
echo "  4. Install tmux plugins: open tmux, press Ctrl-a then I"
echo "  5. Check monitors:    swaymsg -t getoutputs (update sway/config.d/monitors)"
