# gshell

Portable, reproducible CLI shell packaged as a Docker image.

The actual environment is defined in the sister repository [`nix-home-manager`](https://github.com/gschwim/nix-home-manager) (the `linux-x86-docker` / `modules/cli` + `targets/linux` profile, with personal bits disabled).

This repo exists to:

- Pin a specific version of `nix-home-manager` for the Docker image (independent release cadence).
- Provide the canonical place for the Dockerfile, compose examples, publish workflow, and image metadata.
- Make `nix build` here produce the loadable `gshell` image tarball by consuming the `nix-home-cli-image` attribute from the pinned flake.

## Requirements

- Nix (with flakes enabled)
- Docker (to load and run the image)

## Build the image

From this directory:

```bash
nix build
# or explicitly:
nix build .#gshell
```

This produces a result that is the OCI tarball from `dockerTools.buildLayeredImage`.

Load it:

```bash
docker load < result
```

The image will be available locally as `gshell:latest`.

## Run

The container expects a bind-mounted writable home directory (the "real" home on the host provides your persistent files, history, keys, etc.).

```bash
docker run --rm -it \
  -v $HOME/.local/gshell-home:/home/nixuser \
  gshell
```

Inside you get the full zsh + starship + tmux + neovim + python/poetry + networking tools + homectl etc. that the CLI profile provides.

First run will populate `~/.nix-profile` inside the mounted directory (the activation closure is already present in the image layers).

## Recommended host directory

Create it once if you like:

```bash
mkdir -p "$HOME/.local/gshell-home"
```

Subsequent runs will reuse everything (your zsh history, ssh keys if you bind-mount more, nvim state, etc.).

## docker-compose example

See [docker-compose.yml](./docker-compose.yml).

Typical usage:

```bash
docker compose run --rm gshell
# or
docker compose run --rm gshell tmux
```

## Updating the base (pin)

This repo pins `nix-home-manager` via its own `flake.lock`.

To bring in a newer `nix-home-manager` (new tools, fixes, package bumps) into the Docker image:

```bash
nix flake update
nix build
docker load < result
docker tag gshell:latest gshell:YYYYMMDD   # or your versioning scheme
```

Then publish (see below).

## Publishing / tagging

After a successful `docker load`, tag and push to your registry of choice:

```bash
docker tag gshell:latest ghcr.io/gschwim/gshell:latest
docker tag gshell:latest ghcr.io/gschwim/gshell:2026.06.17
docker push ghcr.io/gschwim/gshell:latest
docker push ghcr.io/gschwim/gshell:2026.06.17
```

A small publish helper can live in `scripts/publish.sh` (or a Makefile target) if desired.

## Using the image from a registry in your own Dockerfiles

Once published:

```dockerfile
FROM ghcr.io/gschwim/gshell:latest

# You can add extra bind mounts, env, or use as base for a specialized tool container.
# Note: adding new Nix packages requires rebuilding + republishing a new gshell base.
```

## Entrypoint and behavior

- `ENTRYPOINT`: `zsh`
- `CMD`: `["-i"]`
- `USER`: `nixuser`
- `WORKDIR`: `/home/nixuser`
- `HOME`: `/home/nixuser`
- `SHELL`: zsh from the profile
- The image is intentionally small and headless (no desktop apps).

The PATH is arranged so the home-manager-installed profile (`~/.nix-profile/bin`) takes precedence.

## Relationship to nix-home-manager

- `nix-home-manager` owns the `home.nix`, `modules/cli/`, `targets/linux.nix`, and the `dockerTools.buildLayeredImage` definition (`#nix-home-cli-image`).
- This repo owns the *distribution* of that image as a versioned Docker artifact.
- The `linux-x86-docker` homeConfiguration inside nix-home-manager uses `username = "nixuser"` and `enablePersonal = false`.

See the "Portable Docker / gshell image" section in the nix-home-manager README for more context.

## License

Same as nix-home-manager (whatever you use there).

## Why a separate repo?

Isolating the Docker packaging + pinning lets you:

- Ship image releases on a different schedule than config changes.
- Have a clean `flake.lock` that represents "the exact nix-home-manager that produced this container image".
- Keep publish/CI/compose/Dockerfile concerns out of the main daily-driver home-manager repo.
- Point Docker Hub, GHCR, or internal registries at this repo.

## Development

- All real configuration changes happen in `nix-home-manager`.
- Here you only change pinning, docs, compose files, publish scripts, and the thin Dockerfile reference.
- After changing the pin, always `nix build` + smoke-test a container run before tagging a release.

## Bootstrap note (while landing the paired changes)

The current `flake.lock` pins a specific recent commit of `nix-home-manager` that introduced the `nix-home-cli-image` package / gshell docker support.

- Push the corresponding commit(s) on `nix-home-manager` first (so the rev becomes fetchable from GitHub).
- Then `nix flake update` here if the archive narHash needs to be refreshed.
- A fresh clone of gshell + `nix build` will then work anywhere with network access to GitHub.

Until that push lands, evaluation works on machines that have previously evaluated the tree via a local path override.