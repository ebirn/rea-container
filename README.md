# rea-container

Run [REA](https://github.com/morluto/rea) (Reverse Engineer Anything, an MCP server for
reverse engineering) inside a hardened rootless Podman container.

Multi-stage build on `node:24-trixie-slim`, for linux/amd64 and linux/arm64. Prebuilt upstream
binaries are used wherever they exist (checksums pinned in `SHA256SUMS`); the rest is compiled in
throwaway stages. Everything REA can drive without a commercial license is installed and wired up
through `REA_*` environment variables:

| Purpose | Tools |
|---|---|
| Native decompilation | Ghidra 12.1.4 headless + JDK 21 (arm64: native decompiler built from source), Kuna 1.979, Rizin 0.9.1 (static on amd64, built on arm64), GNU objdump, GDB 16 + pwndbg 2026.09.15 |
| Android | JADX headless MCP 0.7.1, Apktool 3.0.3, adb |
| .NET | ILSpy (`ilspycmd`) + .NET 10 runtime |
| JavaScript / web | Wakaru 1.14.0, Chromium, mitmproxy (`mitmdump`) 12.2.3 |
| Firmware | Binwalk 3.1.0 (built from source), unblob 26.6.4 (+ jefferson, ubi_reader), 7-Zip, squashfs-tools, e2fsprogs, lz4, zstd, lzop, cpio, unar, mtd-utils |
| Network / signals | TShark 4.4, sigrok-cli 0.7.2 |
| WebAssembly | WABT 1.0.42 |
| ELF / crashes | pwntools 4.15.0, pyelftools 0.33, Unicorn 2.1.2 |

Not included: Hopper, IDA and JEB (commercial), Cutter (GUI), Frida, and the Ghidra NativeAOT
extension (needs its own build). `rea doctor` reports Hopper, IDA and agent registrations as
missing; that is expected inside the container.

## Build

    podman build -t rea-sandbox .

## Run

`./run.sh <rea command>` runs any REA command in the hardened container, e.g.
`./run.sh decompile /samples/app entry --provider ghidra`. By hand:

    podman run -i --rm --network=none --cap-drop=ALL \
      --security-opt no-new-privileges --read-only \
      --tmpfs /tmp:rw,size=1g --tmpfs /home/node:rw,size=512m,mode=1777 \
      -v ./samples:/samples:ro,Z -v ./out:/out:rw,Z rea-sandbox

Put targets in `samples/` (read-only mount); results go to `out/`.

## Use with Claude Code

    claude mcp add rea -- podman run -i --rm --network=none --cap-drop=ALL \
      --security-opt no-new-privileges --read-only \
      --tmpfs /tmp:rw,size=1g --tmpfs /home/node:rw,size=512m,mode=1777 \
      -v "$PWD/samples:/samples:ro,Z" -v "$PWD/out:/out:rw,Z" rea-sandbox

Do not run `npx rea-agents setup` on the host; it would add an unsandboxed copy.

## Limits

- Static analysis only: no process/runtime capture of the targets, no Hopper/IDA (commercial/GUI).
- REA itself is not a sandbox; the container is the isolation layer. Keep `--network=none`.
- On macOS, if `podman build` fails with apt signature errors, the Podman VM clock has drifted
  (`podman machine ssh "sudo date -u -s @$(date +%s)"` or restart the machine).
- Large firmware in Ghidra may need more VM memory: `podman machine set --memory 8192`.

## CI

GitHub Actions builds the image on every push, PR and weekly, and runs `rea mcp doctor`
inside the hardened container.
