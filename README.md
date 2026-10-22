# rea-container

Run [REA](https://github.com/morluto/rea) (Reverse Engineer Anything, an MCP server for
reverse engineering) inside a hardened rootless Podman container.

The image contains Node 24, JDK 21, Ghidra headless, binwalk, squashfs-tools, p7zip and
`rea-agents` (version pinned in the `Containerfile`). It runs as a non-root user.

## Build

    podman build -t rea-sandbox .

## Run

    podman run -i --rm --network=none --cap-drop=ALL \
      --security-opt no-new-privileges --read-only \
      --tmpfs /tmp:rw,size=1g --tmpfs /home/node:rw,size=512m \
      -v ./samples:/samples:ro,Z -v ./out:/out:rw,Z rea-sandbox

Put targets in `samples/` (read-only mount); results go to `out/`.

## Use with Claude Code

    claude mcp add rea -- podman run -i --rm --network=none --cap-drop=ALL \
      --security-opt no-new-privileges --read-only \
      --tmpfs /tmp:rw,size=1g --tmpfs /home/node:rw,size=512m \
      -v "$PWD/samples:/samples:ro,Z" -v "$PWD/out:/out:rw,Z" rea-sandbox

Do not run `npx rea-agents setup` on the host; it would add an unsandboxed copy.

## Limits

- Static analysis only: Windows (PE/.NET) and macOS (Mach-O) apps via Ghidra, plus firmware
  unpacking. No runtime capture, no Hopper/IDA (GUI, macOS-only).
- REA itself is not a sandbox; the container is the isolation layer. Keep `--network=none`.
- Large firmware in Ghidra may need more VM memory: `podman machine set --memory 8192`.

## CI

GitHub Actions builds the image on every push, PR and weekly, and runs `rea mcp doctor`
inside the hardened container.
