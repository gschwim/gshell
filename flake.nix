{
  description = "gshell - Isolated packaging and distribution of the portable Nix + Home Manager CLI Docker image.";

  inputs = {
    # Pin the nix-home-manager flake that defines the actual home config
    # and the pre-built docker image attr (nix-home-cli-image -> "gshell" image).
    # This repo "consumes the image attr" as described in nix-home-manager's README.
    nix-home-manager.url = "github:gschwim/nix-home-manager/master";

    # We don't need our own nixpkgs here; we re-export from the pinned source.
  };

  outputs = { self, nix-home-manager, ... }:
    let
      # The docker image is only defined for x86_64-linux (the target runtime).
      system = "x86_64-linux";
    in {
      # Re-export the image package under a clean name for this repo.
      # This lets you build the gshell docker tarball from *this* checkout
      # while the source of truth for the profile lives in the pinned flake.
      #
      # Usage:
      #   nix build .#gshell
      #   docker load < result
      #   docker run --rm -it -v $HOME/.local/gshell-home:/home/nixuser gshell
      packages.${system} = {
        default = nix-home-manager.packages.${system}.nix-home-cli-image;
        gshell = nix-home-manager.packages.${system}.nix-home-cli-image;
      };

      # For advanced use you can reach through to the source flake:
      #   nix eval --raw .#nix-home-manager.homeConfigurations.linux-x86-docker.activationPackage.outPath
      # (the packages.*.gshell is the primary thing this repo exists to publish).
    };
}
