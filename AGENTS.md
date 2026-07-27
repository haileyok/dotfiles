# AGENTS.md

Context for AI agents (and future-hailey) working in this repo. This is a
personal dotfiles repo for **hailey**'s Linux desktop, hosted at
`github.com:haileyok/dotfiles`. Read this before making changes — several
things here look like they "should" be simplified but are deliberately not,
for reasons documented below.

## What this repo is

A Sway (Wayland) desktop environment for **openSUSE Tumbleweed**, managed
with a hybrid of Nix (user-space packages) and plain symlinks (dotfiles).
There is also light, unautomated support for a secondary **macOS** machine
(`.aerospace.toml`, `.zshrc-macos`) — see "Multi-machine notes" below.

Primary hardware: a **Framework Laptop 16** with an **AMD GPU** (Mesa/radeonsi),
a BOE `eDP-1` panel at 2560x1600@165Hz (no output scaling configured — cursor
sizes etc. are chosen for 1x), and a **Logitech MX Master 3S** mouse used
alongside the built-in touchpad.

## Architecture: three tiers, don't blur them

1. **Nix flake (`flake.nix`)** — user-space CLI tools, desktop utilities,
   apps, fonts, zsh plugins. Installed into a single profile entry:
   ```bash
   nix profile install .#default   # first time only — creates profile "dotfiles"
   nix profile upgrade dotfiles    # after any flake.nix edit
   ```
   **Do not re-run `nix profile install .#default` (or `.#desktopTools` etc.)
   after the first install.** The profile entry is already named `dotfiles`
   and tracks `packages.default` (= `allPackages`, the union of every group).
   Installing an attribute again creates a second, colliding package and
   nix will refuse with a "file already provided" error. Always use
   `nix profile upgrade dotfiles` to pick up `flake.nix` changes. (We hit
   this exact error while adding `bibata-cursors` — `upgrade` is the fix.)

2. **System package manager (zypper) — sway, waybar, swayidle, swaylock,
   swaync are intentionally NOT in the nix flake.** Nix-built versions of
   these link against nix's Mesa, which lacks the `radeonsi_dri.so` AMD
   driver. Running the nix version crashes sway immediately after login
   ("Failed to create renderer" / login loop), and because
   `~/.nix-profile/bin` is early in `PATH`, a nix-installed sway would
   silently shadow the working system one. **Never add these packages to
   `flake.nix`.** They're installed via `sudo zypper install sway gtkgreet
   greetd waybar swayidle swaylock swaync` and updated via `zypper`, outside
   this repo's control.

3. **`setup.sh`** — idempotent symlink + bootstrap script. Symlinks repo
   files into `~/.config/*` and `~/`, clones tpm (tmux) and the adi1090x rofi
   theme, patches `.desktop` files to launch GUI/Electron apps through
   `nixGL` (see below), cleans up a known-bad `environment.d` entry, and
   handles SELinux relabeling for the nix store. Safe to re-run.

Because configs are symlinked, editing `~/.config/sway/config` and
`~/dotfiles/sway/config` is editing **the same file** — there is no separate
"deployed" copy to sync.

## Directory map

```
sway/                 Sway compositor config (symlinked to ~/.config/sway)
  config              Main config: keybinds, colors, exec_always, includes config.d/*
  config.d/mouse       Physical mouse (type:pointer) + seat cursor theme
  config.d/touchpad    Touchpad (type:touchpad) — separate natural_scroll policy, see below
  config.d/keyboard    Keyboard input config
  config.d/monitors    Output/resolution config — currently only eDP-1
  config.d/keybinds    Additional keybindings
  config.d/assignments Workspace app assignments
waybar/                Status bar (style.css + config, JSON modules)
swaync/                Notification center (swaync = sway-notification-center)
swaylock/, swayidle/   Lockscreen + idle daemon config
greetd/                Display manager config (config.toml, environment) — installed to
                       /etc/greetd/config.toml manually, not symlinked by setup.sh
ghostty/               Terminal emulator config
zellij/, .tmux.conf    Terminal multiplexers
nvim/                  Neovim config (kickstart.nvim-based)
starship.toml          Shell prompt
bin/                   Scripts on $PATH via .zshrc (e.g. power-profiles.sh for
                       Framework battery charge thresholds; used by waybar)
selinux/               Custom SELinux module (.te) for nix store execution
flake.nix / flake.lock Nix package definitions (see tiers above)
setup.sh               Symlink/bootstrap script
.zshrc                 Linux shell config (this machine)
.zshrc-macos           macOS shell config — NOT wired into setup.sh
.aerospace.toml         macOS tiling WM config (AeroSpace) — NOT wired into setup.sh
README.md              Human-facing install instructions (numbered steps)
```

## Constraints agents must respect

- **Never add sway/waybar/swayidle/swaylock/swaync to `flake.nix`.** See tier
  2 above — this breaks AMD GPU rendering and causes a login loop.
- **GPU/Electron apps need the nixGL wrapper.** Chromium, Slack, Discord,
  Spotify, 1Password, Signal, and ghostty are all patched in `setup.sh` to
  launch via `nixGL <binary>` because nix builds link against nix's Mesa,
  not the system driver. If you add a new nix-installed GUI app, follow the
  same pattern (see the "Patch desktop files for nix compatibility" section
  of `setup.sh`) rather than assuming it'll just work.
- **Locale:** nix's glibc ships without locale data. `LOCALE_ARCHIVE` must
  point at the nix-installed `glibcLocales` archive or nix binaries crash
  with locale warnings/errors. This is set in `.zshrc` (shell-launched
  processes) and documented in `README.md` step 5 for `/etc/environment`
  (sway/greetd-launched processes, which don't go through zsh).
- **Do not use `~/.config/environment.d/` for session env vars.** It was
  tried and abandoned: the `%h` specifier didn't expand correctly in sway's
  launch context, breaking `LOCALE_ARCHIVE`. `setup.sh` actively deletes a
  stale `environment.d/nix.conf` left over from that attempt. The working
  pattern is: **`.zshrc` export (shell-launched apps) + `/etc/environment`
  (everything else, requires sudo + reboot, documented per-var in README)**.
  Follow this same dual pattern for any new session-wide env var (we used it
  for `XCURSOR_THEME`/`XCURSOR_SIZE` when fixing the cursor theme).
- **SELinux is enforcing by default on openSUSE Tumbleweed.** The nix store
  gets labeled `default_t`, which lacks entrypoint permissions — this blocks
  nix-installed zsh as a login shell and blocks systemd from reading
  `nix-daemon.service`. `setup.sh` step 6 relabels the store (`bin_t`) and
  installs `selinux/nix-store-exec.te`. Don't remove this without
  understanding it breaks login.
- **Mouse vs. touchpad scroll direction are intentionally different.**
  `sway/config.d/touchpad` has `natural_scroll enabled` (correct/expected for
  a touchpad). `sway/config.d/mouse` has `natural_scroll disabled` (correct
  for a physical scroll wheel — the MX Master 3S). If "scroll feels
  backwards" comes up again, check which device is misconfigured; don't
  make them match each other.
- **Cursor theme is Bibata-Modern-Classic, set in three places that must
  stay in sync:** `seat seat0 xcursor_theme ...` in
  `sway/config.d/mouse` (compositor-rendered cursor, covers most apps),
  `gsettings ... cursor-theme/cursor-size` in the `exec_always` block of
  `sway/config` (GTK apps), and `XCURSOR_THEME`/`XCURSOR_SIZE` in `.zshrc`
  (XWayland + terminal-launched apps). Changing the theme/size means editing
  all three, plus adding the theme package to `flake.nix` if it's not
  `bibata-cursors`.
- **Hardware assumptions are baked into configs, not detected.** `monitors`
  hardcodes `eDP-1` at a specific resolution/refresh rate; `mouse`/`touchpad`
  assume this specific laptop + this specific external mouse. When editing
  for a different machine, check `config.d/monitors` and run
  `swaymsg -t get_outputs` / `swaymsg -t get_inputs` first rather than
  guessing device names.

## Conventions

- `$mod` = `Mod4` (Super/Windows key). Resize submode on `$mod+r`; direct
  resize binds also exist on `$mod+Ctrl+arrows`.
- Color scheme is Tokyo Night-ish: `$color0 #1a1b26` (bg), `$color7 #a9b1d6`
  (fg/inactive), `$color12 #7aa2f7` (accent/focused border), `$highlight
  #b21858` (rofi/menu accent). Reuse these variables rather than introducing
  new hex literals when touching `sway/config`.
- GTK theme is forced dark (`Adwaita-dark` + `prefer-dark`) via `gsettings`
  in the `exec_always` block — this runs on every `sway reload`, not just
  login, so gsettings-based tweaks (like the cursor settings) take effect
  immediately on reload too.
- Chat/terminal apps get slight transparency: ghostty `0.925`, Slack/Discord
  `0.975`, via `for_window [...] opacity ...` rules in `sway/config`.
- Nvim config is kickstart.nvim-based (see `nvim/README.md` /
  `nvim/lua/kickstart/`) — prefer extending `nvim/lua/custom/plugins/init.lua`
  over restructuring the kickstart base.

## Workflow: testing changes

Most sway/waybar/swaync/swayidle/swaylock changes apply live without logout:

```bash
swaymsg reload                 # sway/config + config.d/* changes
killall -SIGUSR2 waybar        # waybar config/style reload (also bound to $mod+Alt+r)
pgrep -x waybar || waybar       # restart waybar if it died ($mod+Ctrl+b)
```

For input/device changes, verify against the live device list rather than
assuming names/capabilities:

```bash
swaymsg -t get_inputs     # confirm libinput settings actually took (accel, natural_scroll, etc.)
swaymsg -t get_outputs    # confirm monitor names/resolutions before editing config.d/monitors
```

For flake.nix package changes: edit the group list, then
`nix profile upgrade dotfiles` (not `install`, see tier 1 above). New
packages that provide GUI binaries likely need a `setup.sh` desktop-file
patch for nixGL — check whether the app does GPU compositing (almost all
Electron/Chromium-based apps do).

## Multi-machine notes

- `setup.sh` is Linux/openSUSE-specific and assumes root access for steps 3,
  5, and 6. For a machine with only a user account, use
  `nix profile install .#minimal` + the manual symlink list in
  `README.md`'s "Minimal setup" section — no sway/Wayland/desktop configs.
- `.aerospace.toml` (macOS tiling WM) and `.zshrc-macos` exist in the repo
  but have **no bootstrap automation** — no macOS equivalent of `setup.sh`
  exists yet. Treat them as reference configs to manually symlink/adapt, not
  as something `setup.sh` maintains.
- `~/.gitconfig` is **not** managed by this repo (not symlinked, not in
  `setup.sh`) — it's local per-machine identity config.

## When making changes here

- Prefer editing the smallest relevant `config.d/*` file over the monolithic
  `sway/config` when the change is device- or feature-scoped (mouse,
  touchpad, keyboard, monitors, keybinds, assignments already exist as
  separate includes).
- If a change requires a new env var reaching sway/greetd-launched
  processes, remember `environment.d` doesn't work here (see constraints) —
  use the `.zshrc` + `/etc/environment` dual pattern and document the
  `/etc/environment` step in `README.md` like the existing steps.
- If a change requires a new nix package, add it to the right group in
  `flake.nix` (`cliTools`, `desktopTools`, `apps`, `fonts`, `zshPlugins`, or
  `localeData`) — not directly to `allPackages` — and remember
  `nix profile upgrade dotfiles` afterward.
- After any sway config edit, actually run `swaymsg reload` (or ask the user
  to) and spot-check with `swaymsg -t get_inputs`/`get_outputs` rather than
  declaring the change done from reading the config alone.
