{
  description = "gshell - Isolated packaging and distribution of the portable Nix + Home Manager CLI Docker image.";

  inputs = {
    # We pin nix-home-manager only to obtain the home configuration
    # (the CLI profile, packages, neovim, etc.). The Docker image packaging
    # (buildLayeredImage, user setup, entrypoint, Windows compatibility tweaks)
    # is defined here in gshell so the repo is isolated and can produce a
    # working image even if the pinned nix-home-manager's image attr is old.
    nix-home-manager.url = "github:gschwim/nix-home-manager/master";

    # We use a matching nixpkgs for dockerTools and the small wrapper scripts.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nix-home-manager, nixpkgs, ... }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowBroken = true;
        };
      };

      # The docker-specific home-manager configuration (username nixuser,
      # personal bits disabled, linux target).
      dockerHome = nix-home-manager.homeConfigurations.linux-x86-docker;

      # Small entrypoint that lazily activates the baked home-manager profile
      # the first time a container is started against a fresh bind-mounted
      # /home/nixuser. This makes `docker run` against an empty volume "just work".
      #
      # We source hm-session-vars.sh to ensure PATH and other session vars
      # from the home-manager profile are active. We prefer the zsh from the
      # activated profile so that all customizations (starship prompt, aliases,
      # plugins, etc.) are present.
      gshellEntrypoint = pkgs.writeShellScriptBin "gshell-entrypoint" ''
        set -euo pipefail

        export HOME="''${HOME:-/home/nixuser}"

        # Prevent the annoying zsh-newuser-install prompt on first run when no rc files.
        if [ ! -f "$HOME/.zshrc" ]; then
          echo '# Managed by home-manager. Populated by activation.' > "$HOME/.zshrc"
        fi

        # Ensure profile directories exist in the bind-mounted home (the image
        # layers under /home are hidden by the mount at runtime).
        mkdir -p "$HOME/.local/state/nix/profiles"
        mkdir -p "$HOME/.local/state/nix/gcroots"

        PROFILE="$HOME/.nix-profile"
        ACTIVATE="${dockerHome.activationPackage}/activate"
        HM_VARS="$PROFILE/etc/profile.d/hm-session-vars.sh"

        # Always attempt activation on every start. It is idempotent, ensures
        # all home files (.zshrc, starship.toml, nvim config, etc.) are deployed
        # to $HOME from the baked config, and sets up the environment.
        if [ -x "$ACTIVATE" ]; then
          echo "[gshell] Activating home-manager profile..."
          env \
            HOME=/home/nixuser \
            USER=nixuser \
            TMPDIR=/tmp \
            NIX_BUILD_TOP=/tmp \
            NIX_CONF_DIR=/etc/nix \
            XDG_STATE_HOME=/home/nixuser/.local/state \
            "$ACTIVATE" || echo "[gshell] Activation finished (some steps may have warnings)"
        fi

        # After activation, look for a proper profile created by it (XDG or per-user/nixuser).
        # Prefer that for the full profile with packages installed (the profile has bin/ populated).
        # If not, try to find 'home-path' inside the generation (the union of package outputs).
        # Last resort: direct to the generation.
        profile_candidate=""
        for d in "$HOME/.local/state/nix/profiles" "/nix/var/nix/profiles/per-user/nixuser"; do
          if [ -d "$d" ]; then
            p=$(find "$d" -type l \( -name 'profile' -o -name 'profile-*' \) 2>/dev/null | sort | tail -1 || true)
            if [ -n "$p" ]; then
              profile_candidate="$p"
              break
            fi
          fi
        done

        if [ -n "$profile_candidate" ]; then
          if [ "$(readlink -f "$PROFILE" 2>/dev/null || true)" != "$profile_candidate" ]; then
            ln -sfn "$profile_candidate" "$PROFILE" || true
          fi
        else
          # Try home-path inside the activation generation
          home_path=$(find "${dockerHome.activationPackage}" -name home-path -type d 2>/dev/null | head -1 || true)
          if [ -n "$home_path" ]; then
            if [ "$(readlink -f "$PROFILE" 2>/dev/null || true)" != "$home_path" ]; then
              ln -sfn "$home_path" "$PROFILE" || true
            fi
          elif [ ! -e "$PROFILE" ]; then
            ln -sfn "${dockerHome.activationPackage}" "$PROFILE" || true
          fi
        fi

        # Source home-manager session variables (this sets up PATH to include
        # the profile bins, and other env vars from your config).
        if [ -f "$HM_VARS" ]; then
          . "$HM_VARS"
        fi

        # Prefer the zsh from the activated profile (brings custom rc, starship init, etc.)
        ZSH_BIN="$PROFILE/bin/zsh"
        if [ ! -x "$ZSH_BIN" ]; then
          ZSH_BIN="${pkgs.zsh}/bin/zsh"
        fi

        # Ensure we have the HM-managed .zshrc for custom prompt, aliases, etc.
        # Overwrite placeholder if we find the real one in the generation.
        zshrc_gen=$(find "${dockerHome.activationPackage}" -name '.zshrc' -o -name 'zshrc' 2>/dev/null | head -1 || true)
        if [ -n "$zshrc_gen" ]; then
          ln -sfn "$zshrc_gen" "$HOME/.zshrc" || true
        fi

        exec "$ZSH_BIN" -i "$@"
      '';
    in {
      packages.${system} = {
        default = pkgs.dockerTools.buildLayeredImage {
          name = "gshell";
          tag = "latest";

          contents = [
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.nix   # required for the home-manager activation script (it calls nix-build internally)

            # Provide a working sh for any scripts.
            (pkgs.runCommand "bin-sh" {} ''
              mkdir -p $out/bin
              ln -s ${pkgs.bashInteractive}/bin/bash $out/bin/sh
            '')

            # The entrypoint wrapper (we create a stable /bin symlink in extraCommands).
            gshellEntrypoint

            # The complete home-manager activation + profile.
            # This brings in zsh, starship, tmux, neovim (with dotfiles.nvim),
            # python+poetry+scientific stack, networking tools, homectl, etc.
            dockerHome.activationPackage
          ];

          extraCommands = ''
            # Skeleton directories. Real persistent state comes from the
            # bind mount (e.g. -v $HOME/.local/gshell-home:/home/nixuser).
            mkdir -p etc home/nixuser/.local/{bin,state} bin
            mkdir -p home/nixuser/.config
            mkdir -p home/nixuser/.local/state/nix/profiles
            mkdir -p home/nixuser/.local/state/nix/gcroots

            # /tmp is required because home-manager activation uses nix-build
            # which creates temp dirs like /tmp/nix-build-...
            mkdir -p tmp
            chmod 1777 tmp

            # Create the nixuser account (uid 1000) inside the image.
            # This is required so `docker run --user nixuser` works on normal
            # Linux hosts. The account is *not* forced at runtime (see config
            # below) so the image also works on locked-down Windows Docker
            # environments that cannot create matching users or have weird
            # bind-mount ownership.
            cat > etc/passwd <<'EOF'
            root:x:0:0:root:/root:/bin/sh
            nixuser:x:1000:1000::/home/nixuser:/bin/sh
            EOF

            cat > etc/group <<'EOF'
            root:x:0:
            nixuser:x:1000:
            nixbld:x:30000:
            EOF

            # Minimal nix config to avoid 'nixbld' group warning and allow
            # activation to proceed in the container without multi-user nix setup.
            mkdir -p etc/nix
            cat > etc/nix/nix.conf <<'NIXCONF'
build-users-group =
experimental-features = nix-command flakes
NIXCONF

            # Make nix commands available in PATH (usr/local/bin is in the image PATH)
            # so the activation script can find nix-build, nix etc.
            mkdir -p usr/local/bin
            ln -sf ${pkgs.nix}/bin/nix usr/local/bin/nix
            ln -sf ${pkgs.nix}/bin/nix-build usr/local/bin/nix-build
            ln -sf ${pkgs.nix}/bin/nix-env usr/local/bin/nix-env

            # Stable location for the entrypoint.
            ln -sf ${gshellEntrypoint}/bin/gshell-entrypoint bin/gshell-entrypoint
          '';

          config = {
            # We deliberately do not set "User" here.
            # Default is root inside the container. This is the only reliable
            # mode on many locked-down corporate Windows + Docker Business
            # setups (no host user creation, bind mounts arrive owned by root,
            # policies forbid non-root, etc.).
            #
            # On normal Linux you can still run as the unprivileged user:
            #   docker run --user nixuser ...
            #   docker run --user 1000:1000 ...
            #
            # The nixuser entry exists in /etc/passwd (above) so the name works.
            WorkingDir = "/home/nixuser";
            Env = [
              "HOME=/home/nixuser"
              # USER left unset on purpose so it reflects the actual runtime user.
              "SHELL=${pkgs.zsh}/bin/zsh"
              "TERM=xterm-256color"
              "PATH=/home/nixuser/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"
            ];
            Entrypoint = [ "/bin/gshell-entrypoint" ];
            Cmd = [ "-i" ];
          };
        };

        gshell = self.packages.${system}.default;
      };
    };
}
