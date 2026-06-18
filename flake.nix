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

        PROFILE="$HOME/.nix-profile"
        ACTIVATE="${dockerHome.activationPackage}/activate"
        HM_VARS="$PROFILE/etc/profile.d/hm-session-vars.sh"

        if [ ! -e "$PROFILE" ] && [ -x "$ACTIVATE" ]; then
          echo "[gshell] First run with empty home - activating home-manager profile..."
          # Call via bash -c to give the activate script a reliable $0 and environment.
          # This avoids readlink/dirname errors when the script is invoked as an entrypoint.
          bash -c '
            export HOME="'"$HOME"'"
            export USER="${USER:-nixuser}"
            "'"$ACTIVATE"'"
          ' || echo "[gshell] Activation finished (some steps may have warnings)"
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
            EOF

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
