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
    # Engram agent tools: engram (CLI), engram-mcp, engram-config. Public,
    # so it is safe for `.#minimal`. Update with
    # `nix flake lock --update-input engram-garden`.
    engram-garden = {
      url = "github:haileyok/engram-garden";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # MagicPods fork (haileyok forks, branch hailey/mac-parity): upstream +
    # AirPods Mac-parity ports (hi-res mic AAC-ELD over AACP 0x58, Smart
    # Routing handoff, QML controls; goal-001). After forking work: push the
    # branches, then `nix flake lock --update-input magicpods-fork
    # --update-input magicpods-fork-core && nix profile upgrade dotfiles`.
    magicpods-fork = {
      url = "github:haileyok/MagicPodsLinux/hailey/mac-parity";
      flake = false;
    };
    # MagicPodsCore is a git SUBMODULE of the fork — git flake inputs don't
    # materialize submodules, so the core (which carries the Mac-parity
    # ports: hi-res mic + handoff) is its own input pointing at the core
    # fork (branch hailey/handoff: commits 440a1d6 + 29bd9fa on 2.0.10).
    magicpods-fork-core = {
      url = "github:haileyok/MagicPodsCore/hailey/handoff";
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

      # Keep virtual-keyboard event acknowledgements while removing wtype's
      # unconditional 2 ms sleeps after every press and release. This leaves
      # clipboard contents untouched and preserves ordered keystrokes.
      fastWtype = pkgs.wtype.overrideAttrs (old: {
        pname = "wtype-fast";
        postPatch = (old.postPatch or "") + ''
          substituteInPlace main.c --replace-fail 'usleep(2000);' '/* No fixed key delay. */'
          # Keep the virtual keyboard/keymap alive briefly for XWayland clients.
          substituteInPlace main.c --replace-fail \
            'zwp_virtual_keyboard_v1_destroy(wtype.keyboard);' \
            'usleep(200000); zwp_virtual_keyboard_v1_destroy(wtype.keyboard);'
        '';
        postInstall = (old.postInstall or "") + ''
          mv $out/bin/wtype $out/bin/wtype-fast
          rm -f $out/share/man/man1/wtype.1*
        '';
      });

      # btop with GPU panels for both AMD (ROCm) and NVIDIA machines.
      # btop dlopen()s its GPU libraries at runtime. rocmSupport rpaths nix's
      # rocm-smi. For NVIDIA the driver's libnvidia-ml must come from the host,
      # but nix binaries don't search distro lib dirs, and cudaSupport only adds
      # NixOS's /run/opengl-driver/lib. So we also rpath store dirs holding
      # symlinks to each distro's libnvidia-ml; on machines without the NVIDIA
      # driver the symlinks dangle and btop just skips NVIDIA.
      nvmlHostLibDirs = map (dir:
        pkgs.runCommand "nvml-host-link" { } ''
          mkdir -p $out/lib
          ln -s ${dir}/libnvidia-ml.so.1 $out/lib/libnvidia-ml.so.1
          ln -s ${dir}/libnvidia-ml.so.1 $out/lib/libnvidia-ml.so
        '') [
          "/usr/lib/x86_64-linux-gnu" # Ubuntu/Debian
          "/usr/lib64"                # openSUSE/Fedora
        ];

      gpuBtop = (pkgs.btop.override {
        rocmSupport = true;
        cudaSupport = true;
      }).overrideAttrs (old: {
        postPatchelf = (old.postPatchelf or "") + ''
          patchelf --add-rpath ${pkgs.lib.concatMapStringsSep ":" (d: "${d}/lib") nvmlHostLibDirs} $out/bin/btop
        '';
      });

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

      # MagicPodsCore: the background daemon the MagicPods frontend (below)
      # discovers on PATH and launches itself (BackendManager.cpp). Upstream
      # "dependencies/" are FetchContent *stubs* that download sdbus-c++,
      # nlohmann_json, toml++, uSockets, and uWebSockets at configure time —
      # the nix sandbox blocks that, so each is fetched here and pointed at
      # via FETCHCONTENT_SOURCE_DIR_<NAME>. The core has no install() rules,
      # so the binary is installed manually.
      #
      # 2026-10-10: builds from the local fork (~/personal/magicpods-fork,
      # branch hailey/mac-parity) instead of upstream — the fork carries the
      # AirPods Mac-parity ports (goal-001): hi-res mic (AAC-ELD over AACP
      # 0x58, core commit 440a1d6) and Smart Routing handoff (0x10, 29bd9fa),
      # plus the 1024→4096 L2CAP recv-buffer fix (0x58 SDUs exceed 1 KB and
      # SOCK_SEQPACKET silently truncates). ffmpeg (libavcodec/libavutil) is
      # the AAC-ELD decoder. See 0d7x9n-wiry/goal-001-notes.md.
      magicPodsCore = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "magicpodscore";
        version = "2.0.10-mac-parity";
        src = forkSource inputs.magicpods-fork-core;
        sdbusCpp = pkgs.fetchFromGitHub { owner = "Kistler-Group"; repo = "sdbus-cpp"; tag = "v1.6.0"; hash = "sha256-h4eSVBm5VO5ol883dFKoilVGAcQVANNbFFVxKib2D48="; };
        nlohmannJson = pkgs.fetchFromGitHub { owner = "nlohmann"; repo = "json"; tag = "v3.11.3"; hash = "sha256-7F0Jon+1oWL7uqet5i1IgHX0fUw/+z0QwEcA3zs5xHg="; };
        tomlplusplus = pkgs.fetchFromGitHub { owner = "marzer"; repo = "tomlplusplus"; tag = "v3.4.0"; hash = "sha256-h5tbO0Rv2tZezY58yUbyRVpsfRjY3i+5TPkkxr6La8M="; };
        uSockets = pkgs.fetchFromGitHub { owner = "uNetworking"; repo = "uSockets"; tag = "v0.8.7"; hash = "sha256-vf3xI5GOqTEZx8iXf133nQvhUylIRzJ3jGuNUcQk9nY="; };
        uWebSockets = pkgs.fetchFromGitHub { owner = "uNetworking"; repo = "uWebSockets"; tag = "v20.58.0"; hash = "sha256-XSyX6iP+wlUcmBMdfvNyf/uFCzQGmogIS5ehUnRdWs0="; };
        nativeBuildInputs = with pkgs; [ cmake ninja pkg-config ];
        # sdbus-c++ resolves libsystemd through pkg-config (falls back to
        # elogind/basu or a vendored build otherwise — keep those off).
        # ffmpeg_8 = AAC-ELD decode for the hi-res mic (avcodec+avutil).
        buildInputs = with pkgs; [ openssl libpulseaudio bluez zlib systemd ffmpeg_8 ];
        cmakeFlags = [
          "-DCMAKE_BUILD_TYPE=Release"
          "-DBUILD_TESTS=OFF"
          "-DBUILD_CODE_GEN=OFF"
          "-DBUILD_EXAMPLES=OFF"
          "-DBUILD_DOC=OFF"
          "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
          "-DFETCHCONTENT_SOURCE_DIR_SDBUS-CPP=${finalAttrs.sdbusCpp}"
          "-DFETCHCONTENT_SOURCE_DIR_NLOHMANN_JSON=${finalAttrs.nlohmannJson}"
          "-DFETCHCONTENT_SOURCE_DIR_TOMLPLUSPLUS=${finalAttrs.tomlplusplus}"
          "-DFETCHCONTENT_SOURCE_DIR_USOCKETS_CONTENT=${finalAttrs.uSockets}"
          "-DFETCHCONTENT_SOURCE_DIR_UWEBSOCKETS_CONTENT=${finalAttrs.uWebSockets}"
        ];
        installPhase = ''
          runHook preInstall
          install -Dm755 magicpodscore $out/bin/magicpodscore
          runHook postInstall
        '';
        meta = {
          description = "MagicPods background service (fork: AirPods hi-res mic + handoff)";
          homepage = "https://github.com/steam3d/MagicPodsCore";
          mainProgram = "magicpodscore";
          license = pkgs.lib.licenses.gpl3Only;
          platforms = [ "x86_64-linux" ];
        };
      });

      # MagicPods frontend (Qt6/QML). Upstream's cmake install rules deploy a
      # fully self-contained bundle (cqtdeployer-style), which is wrong under
      # nix; like the AUR package, install just the binary, icon, and desktop
      # file and let wrapQtAppsHook handle QML/plugin paths. The frontend
      # finds the magicpodscore backend on PATH (see magicPodsCore above).
      magicPods = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "magicpods";
        version = "1.0.3-mac-parity";
        # 2026-10-10: builds from the local fork (branch hailey/mac-parity)
        # — carries the BatteryPage hi-res mic + handoff controls and the
        # Backend::setCapabilityObject addition (see magicPodsCore above).
        src = forkSource inputs.magicpods-fork;
        nativeBuildInputs = with pkgs; [ cmake ninja qt6.wrapQtAppsHook ];
        buildInputs = with pkgs; [
          qt6.qtbase
          qt6.qtdeclarative
          qt6.qtwebsockets
          qt6.qtsvg
          qt6.qttools # lrelease for qt_add_translations
        ];
        # Skip the portable-bundle deploy script installed by
        # qt_generate_deploy_qml_app_script — nix wrapping replaces it.
        cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];
        installPhase = ''
          runHook preInstall
          install -Dm755 magicpods $out/bin/magicpods
          install -Dm644 ${finalAttrs.src}/src/app/qml/assets/icons/mp-logo-color.svg \
            $out/share/icons/hicolor/scalable/apps/magicpods.svg
          mkdir -p $out/share/applications
          cp ${finalAttrs.desktopItem}/share/applications/*.desktop \
            $out/share/applications/
          runHook postInstall
        '';
        desktopItem = pkgs.makeDesktopItem {
          name = "app.magicpods";
          desktopName = "MagicPods";
          exec = "magicpods";
          icon = "magicpods";
          comment = "Control center for Bluetooth headphones (AirPods, Beats, Galaxy Buds)";
          categories = [ "Utility" ];
          startupWMClass = "MagicPods";
        };
        meta = {
          description = "AirPods, Beats & Galaxy Buds integration for Linux";
          homepage = "https://magicpods.app/linux/";
          mainProgram = "magicpods";
          license = pkgs.lib.licenses.gpl3Only;
          platforms = [ "x86_64-linux" ];
        };
      });

      # Local-fork source filter: cleanSource alone would copy the fork's
      # build/ dirs (500 MB of artifacts) into the store — drop any path
      # inside a "build" directory and .git dirs/files.
      forkSource = root: pkgs.lib.cleanSourceWith {
        src = root;
        filter = path: _type:
          let
            base = baseNameOf path;
            components = pkgs.lib.splitString "/" (toString path);
            inBuild = builtins.elem "build" components;
          in
          !inBuild && base != ".git" && !pkgs.lib.hasSuffix ".git" base;
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
        gpuBtop # AMD + NVIDIA GPU panels, see definition above
        yubikey-manager
        kitty
        coder
        v4l-utils
        gcx
        awscli2
        # Datadog's observability CLI (DataDog/pup, Rust). nixpkgs' `pup` is a
        # different tool (an HTML parser), so always use the `datadog-pup`
        # attribute — it installs the `pup` binary.
        datadog-pup
        inputs.engram-garden.packages.${system}.engram
        atproto-goat
      ];

      # Roast is deliberately NOT in cliTools: it requires cloning a private
      # repo (SSH auth) and per-user gateway credentials, so it must stay out
      # of `.#minimal` and any keyless-machine install. Desktop machines get
      # it via `.#default` / `.#roastTools`.
      roastTools = [
        roastPackage
      ];

      # NOTE: sway, waybar, swayidle, hyprlock, and swaynotificationcenter are
      # intentionally NOT installed via nix. The system (openSUSE RPM) versions
      # are already installed and work correctly with the AMD GPU (Mesa DRI
      # drivers). The nix versions link against nix Mesa, which lacks the
      # radeonsi_dri.so driver, causing sway to crash with "Failed to create
      # renderer" immediately after login — resulting in a login loop.
      # Additionally, nix sway shadows the system sway on PATH, so the broken
      # nix version would take precedence.
      desktopTools = with pkgs; [
        fastWtype
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
        bolt-launcher
        # AirPods/earbud control: MagicPods frontend + its magicpodscore
        # backend. The frontend finds the backend on PATH (see the
        # derivation notes above) — keep them in the same profile. Provides
        # a tray icon (waybar "tray" module).
        magicPods
        magicPodsCore
        # Reverse-engineering toolchain for the AirPods goal (goal-001):
        # Ghidra 12.1.x is the native-binary analysis engine REA
        # (github.com/morluto/rea, npm: rea-agents) expects via
        # GHIDRA_INSTALL_DIR. Java GUI app, but launches headless fine.
        ghidra
      ];

      # (kept out of the apps list) — see apps group comment for purpose.
      # REA also requires a full JDK 21+ (javac present, not just a JRE) with
      # JAVA_HOME exported; .zshrc exports both JAVA_HOME and
      # GHIDRA_INSTALL_DIR pointing into the nix profile.
      reaJdk = [ pkgs.jdk ];

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
      allPackages = cliTools ++ roastTools ++ desktopTools ++ apps ++ fonts ++ zshPlugins ++ localeData ++ reaJdk;

      # Minimal set for machines where you only have a user account (no sudo).
      # No desktop tools, no GUI apps, no Wayland-specific packages.
      # Includes shell, editor, git tools, language runtimes, zsh plugins, and locale data.
      minimalPackages = cliTools ++ zshPlugins ++ localeData;

    in
    {
      packages.${system} = {
        wtype-fast = fastWtype;
        magicpods = magicPods;
        magicpodscore = magicPodsCore;
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
