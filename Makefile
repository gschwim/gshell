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
	@echo "  make run       - run interactive gshell (with host volume)"
	@echo "  make run-tmux  - run inside tmux"
	@echo "  make update    - nix flake update + build (bring in newer base)"
	@echo "  make clean     - remove result symlink"

build:
	# Always build the linux image (this repo only produces x86_64-linux docker images).
	# Works from Linux or from macOS (if you have a linux remote builder configured).
	nix build '.#packages.x86_64-linux.gshell'

load: build
	docker load < result

run: load
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
