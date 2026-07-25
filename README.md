# dotfiles

Linux desktop environment for openSUSE Tumbleweed, managed with [nix](https://nixos.org/) and symlinks.

## Quick start

### 1. Install packages

```bash
nix profile install .#default

# nixGL is required for GPU-accelerated nix apps (ghostty).
# It bridges nix binaries to the system Mesa/OpenGL drivers.
nix profile install github:guibou/nixGL
```

### 2. Symlink configs and clone dependencies

```bash
./setup.sh
```

### 3. Install display manager (requires sudo)

The display manager (greetd) runs as root before login and needs a system-wide
sway binary that the `greeter` user can access. Sway and related Wayland
components are installed via zypper (not nix) because the nix versions link
against nix Mesa, which lacks the AMD GPU DRI drivers — causing sway to crash
on startup with "Failed to create renderer".

```bash
# Install system sway + greetd greeter via zypper
sudo zypper install sway gtkgreet greetd

# Link our greetd config
sudo ln -sf ~/dotfiles/greetd/config.toml /etc/greetd/config.toml

# Enable greetd
sudo systemctl enable greetd
```

> **Why system sway and not nix sway?** The nix-installed sway links against
> nix Mesa, which lacks `radeonsi_dri.so` (the AMD GPU driver). This causes
> sway to crash immediately with "Could not initialize EGL" / "Failed to create
> renderer". The system (zypper) sway at `/usr/bin/sway` links against system
> Mesa with working AMD drivers. Since hailey's PATH puts nix-profile/bin
> first, nix sway would shadow the system sway and take precedence — so sway
> is intentionally excluded from the nix flake. The same applies to waybar,
> swayidle, swaylock, and swaynotificationcenter.

### 4. Set zsh as default shell (requires sudo)

```bash
echo "$HOME/.nix-profile/bin/zsh" | sudo tee -a /etc/shells
chsh -s "$HOME/.nix-profile/bin/zsh"
```

### 5. Set LOCALE_ARCHIVE for the whole session (requires sudo)

Nix binaries use nix's glibc, which doesn't include locale data. The
`LOCALE_ARCHIVE` env var points them to the nix-installed `glibcLocales`
archive. Without it, nix programs launched by sway (before any shell
initialization) crash with "Failed to set locale".

```bash
# Add to /etc/environment so PAM/greetd passes it to sway
echo "LOCALE_ARCHIVE=$HOME/.nix-profile/lib/locale/locale-archive" | sudo tee -a /etc/environment
```

> This requires a reboot to take effect (PAM reads /etc/environment at login).
> The rofi launcher script also sets it inline as a fallback.

### 6. Add your wallpaper

```bash
cp /path/to/wallpaper.png ~/bgs/carcig.png
```

### 7. Post-install

```bash
# Install tmux plugins: open tmux, press Ctrl-a then I (capital i)
# Verify display outputs match your hardware:
swaymsg -t getoutputs
# Edit sway/config.d/monitors if needed
```

## What's included

### Packages (flake.nix)

| Group | Packages |
|-------|----------|
| **CLI tools** | zsh, starship, fzf, eza, bat, gh, uv, go, yarn, yubikey-manager, tmux, zellij, neovim, wl-clipboard, brightnessctl, pokemon-colorscripts |
| **Desktop** | rofi, flameshot, easyeffects, networkmanagerapplet, blueman, thunar, xdg-desktop-portal-wlr |
| **Desktop (system/zypper)** | sway, waybar, swayidle, swaylock, swaynotificationcenter — installed via zypper, not nix, to use system Mesa/GPU drivers |
| **Apps** | chromium, 1password-gui, slack, spotify, discord |
| **Fonts** | FiraCode Nerd Font, JetBrains Mono Nerd Font, Iosevka Nerd Font, Ubuntu |
| **Zsh plugins** | zsh-autosuggestions, zsh-syntax-highlighting, zsh-autocomplete |
| **Locale data** | glibcLocales (fixes locale warnings from nix binaries) |

Install everything at once:

```bash
nix profile install .#default
```

Or install individual groups:

```bash
nix profile install .#cliTools
nix profile install .#desktopTools
nix profile install .#apps
nix profile install .#fonts
nix profile install .#zshPlugins
```

> **Note:** The `apps` group includes unfree packages (1password-gui, slack, spotify).
> `allowUnfree = true` is configured directly in `flake.nix`, so no extra setup is needed.

### Config files (symlinked by setup.sh)

| Dotfile path | Symlink target |
|--------------|----------------|
| `.zshrc` | `~/.zshrc` |
| `.tmux.conf` | `~/.tmux.conf` |
| `starship.toml` | `~/.config/starship.toml` |
| `ghostty/` | `~/.config/ghostty` |
| `nvim/` | `~/.config/nvim` |
| `sway/` | `~/.config/sway` |
| `waybar/` | `~/.config/waybar` |
| `swaync/` | `~/.config/swaync` |
| `swayidle/` | `~/.config/swayidle` |
| `swaylock/` | `~/.config/swaylock` |
| `zellij/` | `~/.config/zellij` |
| `greetd/config.toml` | `/etc/greetd/config.toml` (manual sudo symlink) |
| `selinux/nix-store-exec.te` | SELinux module source (compiled and installed by `setup.sh`) |

### External dependencies (cloned by setup.sh)

- [tpm](https://github.com/tmux-plugins/tpm) — tmux plugin manager → `~/.tmux/plugins/tpm`
- [adi1090x/rofi](https://github.com/adi1090x/rofi) type-2 launcher → `~/.config/rofi/launchers/type-2`

## Nix compatibility modifications

The following changes were made to the original dotfiles to support nix:

### `.zshrc`
- Zsh plugin source paths changed from `/usr/share/zsh/plugins/...` to `~/.nix-profile/share/...`
- Removed `archlinux` oh-my-zsh plugin (Arch-specific)
- Commented out `nvm` source (`/usr/share/nvm/init-nvm.sh`) — not installed via nix
- Commented out `google-cloud-cli` source — not installed via nix
- Commented out `conda` initialization block — not installed via nix
- Fixed typo in `ts` alias (trailing `o`)

### `.tmux.conf`
- tpm init path changed from `/usr/bin/zsh -c "~/.tmux/plugins/tpm/tpm"` to `~/.tmux/plugins/tpm/tpm`

### `sway/config`
- `xdg-desktop-portal` path changed from `/usr/lib/xdg-desktop-portal` to `/usr/libexec/xdg-desktop-portal` (openSUSE path)

## macOS files (ignored)

These files exist in the repo but are not used on Linux:
- `.aerospace.toml` — macOS window manager config
- `.zshrc-macos` — macOS-specific zsh config

## Notes

- The `plugins=(git)` block in `.zshrc` is oh-my-zsh syntax; without oh-my-zsh installed it's a harmless no-op (the git aliases are defined manually below it)
- `sway/config.d/monitors` has hardcoded display outputs (`DP-2`, `HDMI-A-1`) — update these to match your hardware
- System packages (pipewire, dbus, xdg-desktop-portal) are managed by openSUSE/zypper, not nix

## SELinux (openSUSE Tumbleweed)

openSUSE Tumbleweed runs SELinux in **Enforcing** mode by default. Nix store
files get labeled `default_t`, which lacks the `entrypoint` permission needed
for login shells and the `open` permission systemd needs to read service unit
files. This causes two failure modes:

1. **Login loop** — nix-installed zsh (`~/.nix-profile/bin/zsh`) is denied
   `entrypoint`, so PAM sessions die instantly and bounce back to the greeter.
2. **nix-daemon won't start** — systemd can't read `nix-daemon.service` from
   the nix store, so the daemon socket never comes up.

`setup.sh` handles both automatically by:
- Relabeling `/nix/store/*` and `/nix/var/*` as `bin_t` (same context as
  `/usr/bin/*`)
- Relabeling `/nix/var/nix/daemon-socket/*` as `var_run_t` (so systemd can
  create/unlink the socket)
- Installing the `nix-store-exec` SELinux module (from `selinux/nix-store-exec.te`)
  to grant explicit `entrypoint` and `execute` permissions
- Enabling and starting `nix-daemon.socket` and `nix-daemon.service`

If you need to redo this manually:

```bash
sudo semanage fcontext -a -t bin_t '/nix/store/.*'
sudo semanage fcontext -a -t bin_t '/nix/var(/.*)?'
sudo semanage fcontext -a -t var_run_t '/nix/var/nix/daemon-socket(/.*)?'
sudo restorecon -R /nix/store /nix/var
# Compile and install the SELinux module:
checkmodule -M -m -o /tmp/nix-store-exec.mod ~/dotfiles/selinux/nix-store-exec.te
semodule_package -o /tmp/nix-store-exec.pp -m /tmp/nix-store-exec.mod
sudo semodule -i /tmp/nix-store-exec.pp
sudo systemctl enable --now nix-daemon.socket nix-daemon.service
```
