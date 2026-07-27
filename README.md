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

### 5. Set LOCALE_ARCHIVE and NIXOS_OZONE_WL for the whole session (requires sudo)

Nix binaries use nix's glibc, which doesn't include locale data. The
`LOCALE_ARCHIVE` env var points them to the nix-installed `glibcLocales`
archive. Without it, nix programs launched by sway crash.

`NIXOS_OZONE_WL=1` enables native Wayland for Electron apps (Slack, Discord,
Spotify). Without it they launch via XWayland and may not display windows.

Both are set in `.zshrc` for terminal-launched apps, but sway/rofi launches
don't go through zsh, so they need to be in `/etc/environment` too:

```bash
# Add to /etc/environment so PAM/greetd passes them to sway
echo "LOCALE_ARCHIVE=$HOME/.nix-profile/lib/locale/locale-archive" | sudo tee -a /etc/environment
echo "NIXOS_OZONE_WL=1" | sudo tee -a /etc/environment
```

> This requires a reboot to take effect (PAM reads /etc/environment at login).
> The rofi launcher script also exports both as a fallback for the current session.

### 6. Cursor theme (Bibata)

Sway itself picks up the cursor theme from `seat seat0 xcursor_theme` in
`sway/config`, so it takes effect on `swaymsg reload` once
`bibata-cursors` is installed (see step 1). GTK apps are covered by the
`gsettings` calls in `sway/config`, and terminal-launched / XWayland apps
read `XCURSOR_THEME`/`XCURSOR_SIZE` from `.zshrc`.

For full coverage (e.g. anything launched before a shell exists), optionally
add the same vars to `/etc/environment` like step 5:

```bash
echo "XCURSOR_THEME=Bibata-Modern-Classic" | sudo tee -a /etc/environment
echo "XCURSOR_SIZE=24" | sudo tee -a /etc/environment
```

### 7. Add your wallpaper

```bash
cp /path/to/wallpaper.png ~/bgs/carcig.png
```

### 8. Post-install

```bash
# Install tmux plugins: open tmux, press Ctrl-a then I (capital i)
# Verify display outputs match your hardware:
swaymsg -t getoutputs
# Edit sway/config.d/monitors if needed
```

## Minimal setup (user-only machines, no root)

For machines where you only have a user account (no sudo), use the minimal
profile — CLI/dev tools only, no desktop packages:

```bash
# Install minimal package set
nix profile install .#minimal

# Symlink CLI configs only
ln -sf ~/dotfiles/.bashrc ~/.bashrc
ln -sf ~/dotfiles/.zshrc ~/.zshrc
ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf
ln -sf ~/dotfiles/starship.toml ~/.config/starship.toml
ln -sf ~/dotfiles/nvim ~/.config/nvim
ln -sf ~/dotfiles/zellij ~/.config/zellij

# Clone tmux plugin manager
git clone --depth=1 https://github.com/tmux-plugins/tpm.git ~/.tmux/plugins/tpm
```

Includes: zsh, starship, fzf, eza, bat, gh, uv, go, yarn, yubikey-manager,
tmux, zellij, neovim, btop, ghostty, zsh plugins, glibcLocales.
Does NOT include: sway, waybar, rofi, fonts, GUI apps.

## What's included

### Packages (flake.nix)

| Group | Packages |
|-------|----------|
| **CLI tools** | zsh, starship, fzf, eza, bat, gh, uv, go, yarn, yubikey-manager, tmux, zellij, neovim, wl-clipboard, brightnessctl, pokemon-colorscripts |
| **Desktop** | rofi, flameshot, easyeffects, networkmanagerapplet, blueman, thunar, xdg-desktop-portal-wlr |
| **Desktop (system/zypper)** | sway, waybar, swayidle, swaylock, swaynotificationcenter — installed via zypper, not nix, to use system Mesa/GPU drivers |
| **System (zypper)** | tailscale — daemon needs root + systemd (`sudo zypper install tailscale && sudo systemctl enable --now tailscaled`) |
| **System (zypper, laptops only)** | power-profiles-daemon — power profile switching (`sudo zypper install power-profiles-daemon && sudo systemctl enable --now power-profiles-daemon`). Framework laptops support this natively. Not needed on Framework Desktop. |
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
- Added `LOCALE_ARCHIVE` export — nix glibc lacks locale data; points to `glibcLocales` archive
- Added `NIXOS_OZONE_WL=1` export — enables native Wayland for Electron apps (Slack, Discord, Spotify)

### `.tmux.conf`
- tpm init path changed from `/usr/bin/zsh -c "~/.tmux/plugins/tpm/tpm"` to `~/.tmux/plugins/tpm/tpm`

### `sway/config`
- `xdg-desktop-portal` path changed from `/usr/lib/xdg-desktop-portal` to `/usr/libexec/xdg-desktop-portal` (openSUSE path)
- `$term` changed to `nixGL ghostty` — bridges nix binary to system OpenGL/Mesa drivers
- `$lock` simplified — removed unsupported `--effect-blur`, `--effect-vignette`, `--clock` flags (system swaylock 1.8.6 doesn't support them)
- Added `exec swayidle -C ~/.config/swayidle/config` — was missing entirely
- Commented out `workspace 9 output HDMI-A-1` — no external monitor connected

### `swaylock/config`
- Removed `screenshots=true` — not supported by upstream swaylock
- Fixed `ring-color` line — had two color values (syntax error)
- Commented out `indicator-x/y=50` — positioned indicator in top-left corner instead of center

### `swayidle/config`
- Removed backslash-newline continuations — swayidle doesn't support them, caused parse errors

### `waybar/config`
- Changed `hyprland/language` module to `sway/language` — was for wrong compositor

### `sway/config.d/keybinds`
- Removed `bindsym $mod+Return exec xterm` — conflicted with main config's `$term` binding and xterm isn't installed

### `sway/config.d/monitors`
- Updated from `DP-2`/`HDMI-A-1` to `eDP-1` — matches actual laptop display (2560x1600@165Hz)

## macOS files (ignored)

These files exist in the repo but are not used on Linux:
- `.aerospace.toml` — macOS window manager config
- `.zshrc-macos` — macOS-specific zsh config

## Notes

- The `plugins=(git)` block in `.zshrc` is oh-my-zsh syntax; without oh-my-zsh installed it's a harmless no-op (the git aliases are defined manually below it)
- `sway/config.d/monitors` is set for a Framework Laptop 16 (eDP-1, 2560x1600@165Hz) — update to match your hardware
- System packages (pipewire, dbus, xdg-desktop-portal) are managed by openSUSE/zypper, not nix
- `~/.local/share/applications/` contains copies of nix desktop files with ghostty patched for `nixGL`; re-run `./setup.sh` after `nix profile install` to refresh them

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
