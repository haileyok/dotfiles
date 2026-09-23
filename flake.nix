{
  description = "Hailey's dotfiles - Linux desktop environment via nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    roast = {
      # Roast remains a private repo (anonymous HTTPS 404s; git+ssh via the
      # Coder git key works). Pin the current main rev; GitHub exposes this
      # ref, unlike the old d0ae8c9 pin which a history rewrite removed.
      url = "git+ssh://git@github.com/bluesky-social/roast.git?rev=fe38df0b9cf13ae70f767b10f27ab5705c8d55cf";
      flake = false;
    };
  };

  # NOTE: `outputs` must use `...@inputs` and reference `roast` lazily (via
  # `inputs.roast`, only inside roastTools). With a direct
  # `outputs = { self, nixpkgs, roast }:` binding, nix fetches every input
  # during evaluation, so keyless machines would fetch roast before
  # installing `.#minimal`. The roast input is public now, but keeping it
  # lazy still keeps `.#minimal` installs free of the roast fetch/build path.
  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # The public release no longer vendors dependencies (the old pin had a
      # committed vendor/ tree; the new one has an inconsistent one), so nix
      # fetches them via go mod download and we must track the vendor hash.
      roastPackage = pkgs.buildGo127Module {
        pname = "roast";
        version = "0.0.0-dev";
        src = inputs.roast;
        vendorHash = "sha256-rpmONFVRfMPvlFMz31kSYZ9VQTc1UB92Q34bw6v/l0E=";
        subPackages = [ "cmd/roast" ];
        ldflags = [
          "-s"
          "-w"
          "-X github.com/bluesky-social/roast/internal/buildinfo.Version=0.0.0-dev"
          "-X github.com/bluesky-social/roast/internal/buildinfo.Commit=fe38df0"
        ];
        meta = {
          description = "Adversarial cross-model code review CLI";
          homepage = "https://github.com/bluesky-social/roast";
          mainProgram = "roast";
        };
      };

      # All packages needed for the dotfiles, grouped by category.
      # Install everything at once with:
      #   nix profile install .#default
      # Or install individual groups:
      #   nix profile install .#cliTools
      #   nix profile install .#desktopTools
      #   nix profile install .#fonts
      #   nix profile install .#zshPlugins

      cliTools = with pkgs; [
        zsh
        starship
        fzf
        eza
        bat
        gh
        uv
        go
        yarn
        nodejs
        deno
        just
        yubikey-manager
        tmux
        zellij
        neovim
        wl-clipboard
        brightnessctl
        pokemon-colorscripts
        ghostty
        btop
        yubikey-manager
        kitty
        coder
        gcx
      ];

      # Roast is deliberately NOT in cliTools: it requires cloning a private
      # repo (SSH auth) and per-user gateway credentials, so it must stay out
      # of `.#minimal` and any keyless-machine install. Desktop machines get
      # it via `.#default` / `.#roastTools`.
      roastTools = [
        roastPackage
      ];

      # NOTE: sway, waybar, swayidle, swaylock, and swaynotificationcenter are
      # intentionally NOT installed via nix. The system (openSUSE RPM) versions
      # are already installed and work correctly with the AMD GPU (Mesa DRI
      # drivers). The nix versions link against nix Mesa, which lacks the
      # radeonsi_dri.so driver, causing sway to crash with "Failed to create
      # renderer" immediately after login — resulting in a login loop.
      # Additionally, nix sway shadows the system sway on PATH, so the broken
      # nix version would take precedence.
      desktopTools = with pkgs; [
        rofi
        flameshot
        easyeffects
        networkmanagerapplet
        blueman
        thunar
        xdg-desktop-portal-wlr
        bibata-cursors
      ];

      apps = with pkgs; [
        chromium
        _1password-gui
        slack
        spotify
        discord
        signal-desktop
        bitwarden-desktop
        zoom-us
        qalculate-qt
        vlc
      ];

      fonts = with pkgs; [
        nerd-fonts.fira-code
        nerd-fonts.jetbrains-mono
        nerd-fonts.iosevka
        ubuntu-classic
        # Source Han Sans renders reliably in Chromium and other desktop apps.
        source-han-sans
        noto-fonts-color-emoji
      ];

      # nixpkgs' 26.08.03 zsh-autocomplete source contains z-async as a
      # submodule, but its installPhase omits the submodule contents. Without
      # this function the plugin emits "function definition file not found"
      # whenever asynchronous completion runs.
      zAsync = pkgs.fetchFromGitHub {
        owner = "marlonrichert";
        repo = "z-async";
        rev = "5370537de80670b4a97e49cd253d15067709c0a6";
        hash = "sha256-tPosFoZSaUShaRpv7ca9BdOMREfmhnzjd/VKHSshhXo=";
      };

      zshAutocomplete = pkgs.zsh-autocomplete.overrideAttrs (old: {
        installPhase = old.installPhase + ''
          install -Dm755 ${zAsync}/z-async $out/share/zsh-autocomplete/z-async/z-async
        '';
      });

      zshPlugins = with pkgs; [
        zsh-autosuggestions
        zsh-syntax-highlighting
        zshAutocomplete
      ];

      # nix glibc doesn't include locale data, causing locale warnings.
      # glibcLocales provides the archive; LOCALE_ARCHIVE in .zshrc points to it.
      localeData = with pkgs; [
        glibcLocales
      ];

      # nixGL bridges nix binaries to the system OpenGL/Mesa drivers.
      # Required for ghostty (and potentially other GPU-accelerated nix apps).
      # Installed separately: nix profile install github:guibou/nixGL
      # Not included in buildEnv because it uses a different flake input.

      # Convenience: everything in one derivation
      allPackages = cliTools ++ roastTools ++ desktopTools ++ apps ++ fonts ++ zshPlugins ++ localeData;

      # Minimal set for machines where you only have a user account (no sudo).
      # No desktop tools, no GUI apps, no Wayland-specific packages.
      # Includes shell, editor, git tools, language runtimes, zsh plugins, and locale data.
      minimalPackages = cliTools ++ zshPlugins ++ localeData;

    in
    {
      packages.${system} = {
        default = pkgs.buildEnv {
          name = "dotfiles-env";
          paths = allPackages;
          meta.description = "All packages for Hailey's dotfiles";
        };

        # Minimal profile for user-only machines (no root required)
        # Usage: nix profile install .#minimal
        minimal = pkgs.buildEnv {
          name = "dotfiles-minimal";
          paths = minimalPackages;
          meta.description = "CLI/dev tools only — for machines without root access";
        };

        cliTools = pkgs.buildEnv {
          name = "dotfiles-cli-tools";
          paths = cliTools;
        };

        desktopTools = pkgs.buildEnv {
          name = "dotfiles-desktop-tools";
          paths = desktopTools;
        };

        apps = pkgs.buildEnv {
          name = "dotfiles-apps";
          paths = apps;
        };

        fonts = pkgs.buildEnv {
          name = "dotfiles-fonts";
          paths = fonts;
        };

        zshPlugins = pkgs.buildEnv {
          name = "dotfiles-zsh-plugins";
          paths = zshPlugins;
        };

        roastTools = pkgs.buildEnv {
          name = "dotfiles-roast-tools";
          paths = roastTools;
          meta.description = "Roast only — requires private-repo SSH auth; not for keyless machines";
        };
      };
    };
}
