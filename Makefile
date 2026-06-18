# Makefile for common gshell Docker image tasks.
#
# These are thin wrappers. The real work is done by Nix + Docker.
#
# Prerequisites:
#   - nix (flakes)
#   - docker
#
# Typical flow:
#   make build
#   make run
#   make update   # pull newer nix-home-manager pin then rebuild

SHELL := /bin/bash

.PHONY: help build load run run-tmux update clean

help:
	@echo "gshell Makefile targets:"
	@echo "  make build     - nix build the linux image tarball (.#packages.x86_64-linux.gshell)"
	@echo "  make load      - docker load < result"
	@echo "  make run       - run interactive gshell (see README for --user root on Windows)"
	@echo "  make run-tmux  - run inside tmux"
	@echo "  make update    - nix flake update + build (bring in newer base)"
	@echo "  make clean     - remove result symlink"

build:
	# Always build the linux image (this repo only produces x86_64-linux docker images).
	# Works from Linux or from macOS (if you have a linux remote builder configured).
	#
	# When working with local changes in ../nix-home-manager (common during development):
	#   nix build --override-input nix-home-manager path:../nix-home-manager .#packages.x86_64-linux.gshell
	nix build '.#packages.x86_64-linux.gshell'

load: build
	docker load < result

run: load
	# Normal Linux (with dedicated user):
	#   docker run --rm -it --user nixuser -v "$$HOME/.local/gshell-home:/home/nixuser" gshell
	#
	# Default (root) -- good for Windows locked-down or simple cases:
	#   docker run --rm -it -v "$$HOME/.local/gshell-home:/home/nixuser" gshell
	#
	# Locked-down Windows / Docker Business:
	#   docker run --rm -it -v "C:\gshell-home:/home/nixuser" --user root gshell
	docker run --rm -it \
		-v "$$HOME/.local/gshell-home:/home/nixuser" \
		gshell

run-tmux: load
	docker run --rm -it \
		-v "$$HOME/.local/gshell-home:/home/nixuser" \
		gshell tmux

update:
	nix flake update
	$(MAKE) build

clean:
	rm -f result result-* 2>/dev/null || true
