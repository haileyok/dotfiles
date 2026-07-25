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

    # Patch launcher script to set LOCALE_ARCHIVE for nix glibc
    sed -i 's|^rofi \\|LOCALE_ARCHIVE="$HOME/.nix-profile/lib/locale/locale-archive" rofi \\|' \
        "$ROFI_LAUNCHER"
    echo "  ✓ rofi type-2 launcher installed (with nix locale fix)"
fi
echo

# ---------------------------------------------------------------------------
# 4. Wallpaper directory
# ---------------------------------------------------------------------------
echo "--- Creating wallpaper directory ---"
mkdir -p "$HOME/bgs"
echo "  ✓ ~/bgs created (add your wallpaper image here)"
echo "  (sway config references ~/bgs/carcig.png)"
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
