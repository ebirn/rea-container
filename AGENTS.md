# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## What this repo is

A hardened, rootless Podman image that packages [REA](https://github.com/morluto/rea) (`rea-agents` npm package, an MCP server for reverse engineering) with every non-commercial tool it can drive, plus a Claude Code / Codex plugin that runs that image as an MCP server. There is no application code and no test suite; the deliverables are the `Containerfile`, `run.sh`, the CI workflow and the plugin files.

## Commands

    podman build -t rea-sandbox .            # build locally (the tag run.sh expects)
    ./run.sh doctor --json                   # REA doctor in the hardened container (exits non-zero; see below)
    ./run.sh mcp doctor --json               # MCP self-check; CI requires "healthy": true
    ./run.sh decompile /samples/app entry --provider ghidra

`run.sh` mounts `./samples` read-only at `/samples` and `./out` writable at `/out`, with `--network=none --cap-drop=ALL --read-only`. Keep those flags; the container is the only isolation layer (REA is not a sandbox). Never suggest `npx rea-agents setup` on the host.

`rea doctor` is expected to fail on Hopper, IDA and agent registrations. CI only asserts a fixed list of `scope_checks` (ghidra, jadx, kuna, ilspycmd); if you add a tool that must be verified, extend that `required` list in `.github/workflows/build.yml`, and add its version command to the "Tool versions" step.

## Containerfile architecture

Multi-stage, for linux/amd64 and linux/arm64 (`TARGETARCH`). Each tool is fetched or compiled in a throwaway stage (`fetch`, `ghidra-decompiler`, `rizin`, `binwalk`, `pyenv`, `ilspy`) and only the results are `COPY --from`-ed into the final `runtime` stage, which also installs apt packages, `rea-agents@${REA_VERSION}`, and wires every tool via `REA_*` env vars. Entrypoint is `rea`, default `CMD` is `mcp`.

Conventions to preserve when adding or bumping a tool:
- Prebuilt upstream binaries are downloaded with the `dl <name> <url>` helper in the `fetch` stage, which verifies the file against `SHA256SUMS` (entry name must match exactly, including per-arch names such as `wabt-...-x64` vs `-arm64`). Updating a version means updating the `ARG`, the URL, and the matching `SHA256SUMS` line(s) for both architectures.
- Tools with no binary for an arch are built from source (arm64 Ghidra decompiler, arm64 Rizin, Binwalk 3 on both).
- Each new tool needs a `REA_*` env var in the `runtime` stage so REA discovers it.
- Wrappers (`apktool`, `chromium-container` with `--no-sandbox`) are generated inline in the `runtime` stage.
- Tool versions are duplicated in the `README.md` table; keep it in sync.

## Version policy

Tool versions follow what the pinned `rea-agents` release verifies, not the newest upstream release. Bump `REA_VERSION` first, then read the pins from the npm package (`npm pack rea-agents@<version>`): `dist/generatedPackageMetadata.js` (`pinnedNodeVersion`, used for the exact `NODE_IMAGE` tag), the `dist/**/*Release.js` files (Kuna, JADX MCP, WABT, Wakaru, pwntools), `dist/contracts/firmware/firmwareToolRequirements.js` (Binwalk, unblob), `dist/ghidra/GhidraReleasePolicy.js` (Ghidra) and `third_party/*/README.md` (pwndbg). Use exactly those versions, even if that is a downgrade. Only tools REA does not pin (Apktool, Rizin, ilspycmd, apt packages) go to the latest release.

## CI and publishing

`.github/workflows/build.yml` builds natively per arch (amd64 and arm64 runners), runs the doctor checks, and on `main` and on `v*` tags pushes `ghcr.io/ebirn/rea-container:<sha>-<arch>`; the `manifest` job then joins them into multi-arch tags: `:main` and `:<sha>` for `main`, `:vX.Y.Z` and `:latest` for a release tag. `:latest` (what the plugin runs) therefore only moves on releases. It also runs weekly to pick up upstream changes, which publishes `:main` only.

Releases are GitHub releases tagged `v<plugin version>` on `main`. Bump the plugin version (both `plugin.json` files) in the same PR as the change it releases; a tag build fails if the tag does not match both `plugin.json` versions. Publishing the release creates the tag, which builds and publishes `:vX.Y.Z` and moves `:latest`.

## Plugin layout (`plugins/rea-container/`)

The same plugin is published for two hosts via two marketplace files: `.claude-plugin/marketplace.json` (Claude Code) and `.agents/plugins/marketplace.json` (Codex), both pointing at `./plugins/rea-container`.

- `plugin.json` (Codex, with `$schema` and `extensions.com.openai.interface`) and `.claude-plugin/plugin.json` (Claude, `displayName`) are near-duplicates; edit both when changing name, version or description.
- `.mcp.json` (Claude) and `mcp.json` (Codex, adds `$schema` and `"type": "stdio"`) hold the same `podman run` command; keep their args identical. They run the published GHCR image, mount the agent's working directory read-only at `/samples`, and use the named volume `rea-out` for `/out`. They also set `--label=io.github.ebirn.rea-container=mcp`, which the README and the `rea-container` skill use to find and remove idle per-session containers; keep the label when changing the args. This differs from `run.sh`, which uses the local `rea-sandbox` tag and bind mounts.
- `skills/rea-container/SKILL.md` documents the container's path rules (`/samples/...`) for the agent using the plugin; `skills/reverse-engineer-anything/` is vendored verbatim from `skills/reverse-engineer-anything/` in the `rea-agents` npm package matching `REA_VERSION` (licence in `LICENSE-REA`). Do not edit it; when bumping REA, replace the directory with the package's copy and keep `LICENSE-REA`.
