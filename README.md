# gshell

Portable, reproducible CLI shell packaged as a Docker image.

The actual environment is defined in the sister repository [`nix-home-manager`](https://github.com/gschwim/nix-home-manager) (the `linux-x86-docker` / `modules/cli` + `targets/linux` profile, with personal bits disabled).

This repo exists to:

- Pin a specific version of `nix-home-manager` for the Docker image (independent release cadence).
- Provide the canonical place for the Dockerfile, compose examples, publish workflow, and image metadata.
- Own the Docker image construction (user setup for Linux + root default for locked-down Windows, entrypoint, layered image) so gshell can produce a working `gshell` image independently of the state of nix-home-manager's image attr.

## Requirements

- Nix (with flakes enabled)
- Docker (to load and run the image)

## Build the image

The image is **Linux-only** (`x86_64-linux`).

### On a Linux machine

```bash
nix build
# or
nix build .#gshell
# or explicitly
nix build .#packages.x86_64-linux.gshell
```

Or just:

```bash
make build
```

### On macOS (or other non-Linux)

You must select the Linux package explicitly:

```bash
nix build .#packages.x86_64-linux.gshell
```

Or use the `--system` flag:

```bash
nix build --system x86_64-linux .#gshell
```

Or use the Makefile (now safe from any host):

```bash
make build
```

If you don't have a Linux builder configured, this will fail at *build* time (evaluation usually succeeds). See "Building from macOS" below.

After the build succeeds you get a `result` that is the tarball:

```bash
docker load < result
```

The image will be available locally as `gshell:latest`.

**Important when developing alongside nix-home-manager:**

gshell now defines the Docker image itself (see flake.nix). It only uses nix-home-manager for the home configuration.

A plain `nix build` should work once the lock is updated for the new nixpkgs input.

If you have uncommitted changes in `../nix-home-manager`:

```bash
nix build --override-input nix-home-manager path:../nix-home-manager .#packages.x86_64-linux.gshell
docker load < result
```

After changes land in nix-home-manager, update here with:

```bash
nix flake update
nix build ...
```

### Running the container (user & permissions)

The image creates a `nixuser` account (uid/gid 1000) inside the container (see /etc/passwd), but **does not force it** at runtime.

- **Default**: runs as root. This is the most compatible setting for restricted environments.
- On normal Linux: `docker run --user nixuser ...` (or `--user 1000:1000`)
- On Windows / locked-down Docker: usually you must run as root (see Windows section below).

On first start with a fresh/empty bind-mounted home, the entrypoint automatically runs the baked-in home-manager activation.

### Volume mount best practices

Use a dedicated directory:

```bash
mkdir -p "$HOME/.local/gshell-home"
docker run --rm -it -v "$HOME/.local/gshell-home:/home/nixuser" gshell
```

Bind mount ownership is host-dependent. On Linux the directory is usually owned by the user inside the container. On Windows the mount often appears owned by root (or a mapped id) from inside the container.

### Locked-down Windows + Docker Business

This image is intended to work in highly restricted corporate Windows environments (Docker Business / Docker Desktop with policies, limited volume paths, no host user management, etc.).

**Recommended invocation on Windows:**

```powershell
# Example paths (adjust to what your environment allows)
mkdir -p C:\gshell-home   # or a path you are permitted to use

docker run --rm -it `
  -v "C:\gshell-home:/home/nixuser" `
  --user root `
  gshell
```

Key points for locked-down Windows:

- Run with `--user root` (or omit it — root is now the default).
- You generally **cannot** rely on `--user nixuser` or uid 1000 because:
  - You have no access to create a matching user on the Windows host.
  - Bind mounts from Windows to the Linux container VM have very limited uid/gid semantics.
- The bind mount target inside the container is always `/home/nixuser` (this is by design for the home-manager profile).
- Choose a volume source path that your organization's Docker policy allows. Many locked-down setups only permit specific directories or drives.
- The automatic activation on first run still works when running as root.
- If you only have PowerShell, use the backtick+newline style or put the command in a small .bat / .ps1 wrapper.

**docker-compose on Windows (example):**

```yaml
services:
  gshell:
    image: gshell:latest
    stdin_open: true
    tty: true
    volumes:
      - C:\gshell-home:/home/nixuser
    user: "root"          # important on restricted Windows
```

You can also pass `user: root` via command line:

```bash
docker compose run --user root --rm gshell
```

If even root is problematic in your environment, the container is still usable; the profile tools live in the nix store regardless of the runtime user.

## Run

The container expects a bind-mounted writable home directory (the "real" home on the host provides your persistent files, history, keys, etc.).

```bash
docker run --rm -it \
  -v "$HOME/.local/gshell-home:/home/nixuser" \
  gshell
```

### Building from macOS

`gshell` only produces an `x86_64-linux` Docker image. On macOS:

- Evaluation of `.#packages.x86_64-linux.gshell` works.
- Realizing (building) the derivation requires a Linux builder.

Common options:

1. **Remote Linux builder** (recommended for local dev)
   - Run a Linux VM (Lima + NixOS, or a cheap cloud box, or a local Ubuntu box).
   - Register it in `/etc/nix/machines` or via `nix build --builders 'ssh-ng://user@linux-builder x86_64-linux ...'`.
   - Then the commands above will transparently build on Linux.

2. **CI / one-off Linux shell**
   - Use GitHub Actions, a temp Linux CI runner, or `nix develop` on a Linux machine.
   - Many teams do the `nix build .#packages.x86_64-linux.gshell && docker load` step only in CI for publishing.

3. **Just evaluate / inspect**
   ```bash
   nix eval .#packages.x86_64-linux.gshell.outPath   # shows the store path if cached
   ```

Once the tarball is produced (by whatever means), `docker load` and `docker run` work on macOS just fine — only the *build* of the image tarball itself is Linux-specific.

## Run

See the "Running the container (user & permissions)" and the platform-specific sections above (especially **Locked-down Windows + Docker Business**).

Basic pattern (Linux/macOS normal case):

```bash
docker run --rm -it \
  -v "$HOME/.local/gshell-home:/home/nixuser" \
  gshell
```

Inside you get the full zsh + starship + tmux + neovim + python/poetry + networking tools + homectl etc.

The first run against a fresh volume will run the activation entrypoint automatically.

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
nix build .#packages.x86_64-linux.gshell
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
- After changing the pin, always `nix build .#packages.x86_64-linux.gshell` + smoke-test a container run before tagging a release.

## Bootstrap note (while landing the paired changes)

The current `flake.lock` pins a specific recent commit of `nix-home-manager` that introduced the `nix-home-cli-image` package / gshell docker support.

- Push the corresponding commit(s) on `nix-home-manager` first (so the rev becomes fetchable from GitHub).
- Then `nix flake update` here if the archive narHash needs to be refreshed.
- A fresh clone of gshell + `nix build .#packages.x86_64-linux.gshell` will then work anywhere with network access to GitHub.

Until that push lands, evaluation works on machines that have previously evaluated the tree via a local path override.