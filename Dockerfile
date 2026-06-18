# syntax=docker/dockerfile:1
#
# gshell Dockerfile
#
# PURPOSE
# -------
# This Dockerfile serves two roles:
#
# 1. Reference / documentation for the image contract (labels, user, entrypoint,
#    volume expectations, etc.).
#
# 2. Extension point: once the image is published to a registry you (or CI)
#    can do:
#      FROM ghcr.io/gschwim/gshell:...
#    and add company-specific mounts, env, or light wrappers.
#
# THE REAL IMAGE IS BUILT WITH NIX
# ---------------------------------
# The production artifact is produced by:
#
#   nix build .#gshell
#   docker load < result
#
# (see flake.nix which pins nix-home-manager and re-exports its
#  dockerTools.buildLayeredImage package "nix-home-cli-image").
#
# dockerTools gives us:
# - Perfectly reproducible layers derived from the exact nix store paths
# - The full home-manager activation closure (zsh, starship, tmux, neovim + dotfiles.nvim,
#   python + poetry + scientific stack, networking tools, homectl, etc.)
# - Correct User / Entrypoint / Env / WorkingDir baked in
#
# You normally never run "docker build" to produce the base gshell image.
# If you want to use Docker build tooling for publishing or multi-arch,
# the recommended flow is still: build the tar via nix on an x86_64-linux
# machine (or with a remote builder), load it, then tag + push.
#
# ADDING NEW PACKAGES
# -------------------
# Do not try to apt/pip install inside a running gshell container for permanence.
# Instead:
#   - edit the profile in nix-home-manager (modules/cli/packages.nix or targets/linux.nix)
#   - bump the pin in this repo's flake.lock
#   - rebuild + republish
#
# This keeps the container 100% reproducible and identical to what you get
# on bare metal after a home-manager switch (headless profile).

FROM scratch

# We cannot meaningfully populate a scratch image here because the content
# lives in the Nix store closure. When you "docker load" the tar produced by
# nix, you get the real layers + config below.

# The following metadata is what the loaded image will also carry
# (dockerTools sets most of it; these labels are for humans + registries).
LABEL org.opencontainers.image.title="gshell"
LABEL org.opencontainers.image.description="Portable CLI environment (Nix + home-manager)"
LABEL org.opencontainers.image.source="https://github.com/gschwim/gshell"
LABEL org.opencontainers.image.licenses="MIT"   # adjust if nix-home-manager uses something else

# When extending after a registry push, you will see these values from the base:
#   User:        nixuser
#   WorkingDir:  /home/nixuser
#   Entrypoint:  ["/nix/store/.../bin/zsh"]
#   Cmd:         ["-i"]
#   Env:         HOME=/home/nixuser, USER=nixuser, SHELL=..., PATH=...
#
# Recommended runtime usage (bind mount your real home dir for persistence):
#
#   docker run --rm -it \
#     -v $HOME/.local/gshell-home:/home/nixuser \
#     gshell
#
# Or with compose (see docker-compose.yml).
#
# Nothing else belongs in this file for the base image.
# Keep it tiny and honest.