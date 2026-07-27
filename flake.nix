{
  description = "Hailey's dotfiles - Linux desktop environment via nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
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
        yubikey-manager
        tmux
        zellij
        neovim
        wl-clipboard
        brightnessctl
        pokemon-colorscripts
        ghostty
        btop
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
      ];

      apps = with pkgs; [
        chromium
        _1password-gui
        slack
        spotify
        discord
      ];

      fonts = with pkgs; [
        nerd-fonts.fira-code
        nerd-fonts.jetbrains-mono
        nerd-fonts.iosevka
        ubuntu-classic
      ];

      zshPlugins = with pkgs; [
        zsh-autosuggestions
        zsh-syntax-highlighting
        zsh-autocomplete
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
      allPackages = cliTools ++ desktopTools ++ apps ++ fonts ++ zshPlugins ++ localeData;

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
      };
    };
}
