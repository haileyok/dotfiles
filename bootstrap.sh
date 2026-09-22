#!/usr/bin/env bash
#
# bootstrap.sh — Coder workspace bootstrap, run automatically by the Coder
# dotfiles module (registry.coder.com/coder/dotfiles) on every workspace
# start, including brand-new workspaces with empty home volumes.
#
# Coder runs the first setup script it finds in this order:
#   install.sh, install, bootstrap.sh, bootstrap, script/bootstrap,
#   setup.sh, setup, script/setup
# This file intentionally outranks setup.sh (the openSUSE desktop script);
# neither should be merged into the other.
#
# Idempotent: every step is guarded, so re-runs on each start are fast no-ops.
# Assumes a headless Linux container as root with /root on a persistent
# volume and /nix on a persistent subPath mount (bluesky-social/deploy
# templates/coder-kubernetes). Requires curl and git only.
#
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CONFIG_DIR="${HOME}/.config"

echo "=== Coder workspace bootstrap ==="
echo "Source: $DOTFILES_DIR"
echo

# ---------------------------------------------------------------------------
# 1. Nix (single-user, no daemon — nothing privileged in a container)
# ---------------------------------------------------------------------------
if ! command -v nix >/dev/null 2>&1 && [ ! -x "$HOME/.nix-profile/bin/nix" ]; then
    echo "--- Installing nix (single-user, --no-daemon) ---"
    # The nix installer unpacks an xz-compressed tarball; bare Ubuntu
    # containers lack xz-utils (and the installer's curl progress needs curl,
    # which the workspace template provides). Install prerequisites first —
    # apt in a container needs no sudo when running as root.
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends xz-utils ca-certificates
    fi
    # The single-user installer is not root-aware: when the nix binary runs
    # as root it insists on the multi-user nixbld build group (the bundled
    # nix.conf sets build-users-group = nixbld), and aborts with "the group
    # 'nixbld' ... does not exist". The standard container fix (same as the
    # official Nix docker images) is to create the group and build users
    # first; the installer then completes, and binary substitution from
    # cache.nixos.org works without ever needing the daemon.
    if [ "$(id -u)" = "0" ]; then
        # Clean slate from any failed attempt. NOTE: in Coder workspaces /nix
        # is a persistent volume mountpoint (the template's subPath mount), so
        # the directory itself cannot be removed — only its contents. We only
        # reach this branch when nix is not installed, so anything inside is
        # partial garbage from a failed attempt.
        rm -rf "$HOME/.nix-profile"
        find /nix -mindepth 1 -delete 2>/dev/null || true
        if ! getent group nixbld >/dev/null 2>&1; then
            groupadd -r nixbld
            for n in $(seq 1 32); do
                useradd -r -g nixbld -G nixbld -c "Nix build user $n" \
                    -d /var/empty -s /usr/sbin/nologin "nixbld$n"
            done
        fi
        sh <(curl -L https://nixos.org/nix/install) --no-daemon
    else
        sh <(curl -L https://nixos.org/nix/install) --no-daemon
    fi
fi
# shellcheck disable=SC1091
. "$HOME/.nix-profile/etc/profile.d/nix.sh" \
    || . /nix/var/nix/profiles/default/etc/profile.d/nix.sh

# Fresh single-user installs have no user nix.conf, so the experimental
# `nix-command` and `flakes` features are off and `nix profile install .#…`
# (a flake reference) fails. Enable them for this user — same as the desktop
# setup's ~/.config/nix/nix.conf. The profile install below is the only nix
# command that needs it at bootstrap time.
if [ ! -f "$HOME/.config/nix/nix.conf" ]; then
    mkdir -p "$HOME/.config/nix"
    printf 'experimental-features = nix-command flakes\n' > "$HOME/.config/nix/nix.conf"
fi

# ---------------------------------------------------------------------------
# 2. Minimal package profile (zsh, starship, fzf, eza, bat, gh, tmux, zellij,
#    neovim, ghostty, coder, zsh plugins — see flake.nix `minimal`; roast is
#    deliberately excluded: private-repo + credentials, not for keyless
#    workspace bootstrap)
#    Install once; do NOT upgrade on every start (slow, and AGENTS.md warns
#    against re-running `nix profile install` for an existing entry).
# ---------------------------------------------------------------------------
if [ ! -e "$HOME/.nix-profile/bin/zsh" ]; then
    echo "--- Installing minimal nix profile (first run; takes a few minutes) ---"
    (cd "$DOTFILES_DIR" && nix profile install .#minimal)
else
    echo "  ✓ nix profile already installed (upgrade manually: nix profile upgrade minimal)"
fi
echo

# ---------------------------------------------------------------------------
# 3. CLI-only config symlinks (README "Minimal setup" list — no desktop or
#    Wayland configs; see AGENTS.md "three tiers, don't blur them")
# ---------------------------------------------------------------------------
echo "--- Symlinking CLI configs ---"
link_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        return
    fi
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        echo "  WARNING: $dst exists and is not a symlink — backing up to ${dst}.bak"
        mv "$dst" "${dst}.bak"
    fi
    ln -sfn "$src" "$dst"
    echo "  ✓ $dst -> $src"
}

link_file "$DOTFILES_DIR/.zshrc"      "$HOME/.zshrc"
link_file "$DOTFILES_DIR/.bashrc"     "$HOME/.bashrc"
link_file "$DOTFILES_DIR/.tmux.conf"  "$HOME/.tmux.conf"
link_file "$DOTFILES_DIR/starship.toml" "$CONFIG_DIR/starship.toml"
link_file "$DOTFILES_DIR/nvim"        "$CONFIG_DIR/nvim"
link_file "$DOTFILES_DIR/zellij"      "$CONFIG_DIR/zellij"
link_file "$DOTFILES_DIR/git"         "$CONFIG_DIR/git"
echo

# ---------------------------------------------------------------------------
# 4. Work git identity override
# ---------------------------------------------------------------------------
# ~/.config/git/config carries the personal identity (me@haileyok.com); it is
# the XDG fallback. ~/.gitconfig takes precedence over it, so a work machine
# overrides here rather than editing the repo (per AGENTS.md multi-machine
# notes). Persists on the home volume.
if [ -f "$HOME/.gitconfig" ] && ! grep -q '\[user\]' "$HOME/.gitconfig"; then
    # gitconfig exists (e.g. created by a credential helper) but has no
    # identity — only add the identity block, don't clobber the rest.
    {
        echo ""
        echo "[user]"
        echo "  name = hailey"
        echo "  email = hailey@blueskyweb.xyz"
    } >> "$HOME/.gitconfig"
    echo "  ✓ work identity added to ~/.gitconfig"
elif [ ! -f "$HOME/.gitconfig" ]; then
    printf '[user]\n  name = hailey\n  email = hailey@blueskyweb.xyz\n' > "$HOME/.gitconfig"
    echo "  ✓ work identity written to ~/.gitconfig"
else
    echo "  ✓ ~/.gitconfig already has an identity — leaving it alone"
fi
echo

# ---------------------------------------------------------------------------
# 5. tmux plugin manager (tpm)
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
# 6. Ghostty terminfo (for SSH/coder ssh from a Ghostty terminal)
# ---------------------------------------------------------------------------
# Same rationale as setup.sh step 1c: TERM=xterm-ghostty must resolve in
# ~/.terminfo or zsh-autocomplete duplicates characters. .zshrc also
# self-heals this on first start; this makes it deterministic.
echo "--- Installing xterm-ghostty terminfo into ~/.terminfo ---"
GHOSTTY_TERMINFO_SRC="$DOTFILES_DIR/terminfo/xterm-ghostty.terminfo"
if [ -r "$GHOSTTY_TERMINFO_SRC" ] && command -v tic >/dev/null 2>&1; then
    TERMINFO="$HOME/.terminfo" tic -x -o "$HOME/.terminfo" "$GHOSTTY_TERMINFO_SRC" >/dev/null 2>&1 \
        && echo "  ✓ xterm-ghostty installed"
else
    echo "  WARNING: tic or terminfo source unavailable — .zshrc will self-heal on first start"
fi
echo

# ---------------------------------------------------------------------------
# 7. Shell setup: nix on PATH via .bashrc — NEVER chsh in a workspace.
# ---------------------------------------------------------------------------
# chsh writes /etc/passwd in the disposable container layer. If a workspace
# agent restarts (or the pod is recreated) at any moment when the nix profile
# link is not yet resolvable — /nix still mounting, profile mid-upgrade — the
# login shell points at a missing binary and every SSH session dies instantly
# with exit 127, locking you out of an otherwise-healthy workspace. This
# happened in production: bootstrap completed and chsh'd, agent restarted
# minutes later, all logins failed. Instead, keep /bin/bash as the login
# shell and put nix + zsh on PATH through .bashrc so a broken nix degrades
# to "tools missing", never "cannot log in".
echo "--- Shell setup ---"
# Repair a /etc/passwd left pointing at the nix zsh by an older bootstrap.
ROOT_SHELL="$(grep '^root:' /etc/passwd | cut -d: -f7)"
if [ -n "$ROOT_SHELL" ] && [ "$ROOT_SHELL" != "/bin/bash" ] && [ "$ROOT_SHELL" != "/bin/sh" ]; then
    sed -i "s|^root:\(.*\):$ROOT_SHELL\$|root:\1:/bin/bash|" /etc/passwd \
        && echo "  ✓ root login shell reset to /bin/bash (was $ROOT_SHELL)"
fi
# Ensure interactive shells get nix on PATH and drop into zsh when available.
BASHRC_NIX_BLOCK='# --- added by dotfiles bootstrap (coder workspace) ---'
if ! grep -q "$BASHRC_NIX_BLOCK" "$HOME/.bashrc" 2>/dev/null; then
    {
        echo ""
        echo "$BASHRC_NIX_BLOCK"
        echo '. "$HOME/.nix-profile/etc/profile.d/nix.sh" 2>/dev/null || true'
        echo "command -v zsh >/dev/null 2>&1 && [ -x \"\$HOME/.nix-profile/bin/zsh\" ] && exec \"\$HOME/.nix-profile/bin/zsh\" -l"
    } >> "$HOME/.bashrc"
    echo "  ✓ nix PATH + zsh auto-exec added to ~/.bashrc"
else
    echo "  ✓ ~/.bashrc already configured"
fi
echo

echo "=== Bootstrap complete ==="
echo "Next steps:"
echo "  1. Restart your shell or run: exec \$SHELL"
echo "  2. Open tmux and press Ctrl-a then I to install tmux plugins"
echo "  3. To add packages: edit flake.nix, then 'nix profile upgrade minimal'"
