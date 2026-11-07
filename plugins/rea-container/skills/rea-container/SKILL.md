---
name: rea-container
description: How the sandboxed REA server sees files. Use before calling REA tools in this plugin, whenever a target path, firmware image, binary, APK, pcap or output location is needed.
---

# REA in a container

The REA MCP server runs inside an offline, rootless Podman container. Host paths do not exist there.

- **Targets:** the directory the agent was started in is mounted read-only at `/samples`. A host
  file `./firmware/radio.bin` is `/samples/firmware/radio.bin`. Always pass `/samples/...` paths
  to REA tools. Files outside the project directory are not visible.
- **Output:** `/out` is the only writable location (named Podman volume `rea-out`). Copy results
  to the host with
  `podman run --rm -v rea-out:/out:ro -v "$PWD":/dst docker.io/library/busybox cp -r /out/. /dst/`.
- **No network:** nothing can be downloaded; targets are analysed statically and never executed
  on the host.
- **Available:** Ghidra (with decompiler), JADX, Apktool, Kuna, Rizin, objdump, GDB/pwndbg, ILSpy,
  Wakaru, mitmdump, TShark, sigrok-cli, WABT, Binwalk 3.1, unblob, pwntools, Chromium, adb.
- **Not available:** Hopper, IDA, JEB, Frida, process/runtime capture of the target. Reports of
  missing agent registrations or Hopper/IDA from `doctor` are expected.
- If a tool fails because the image is missing, run `podman pull ghcr.io/ebirn/rea-container:latest`
  (about 1.5 GB) and restart the session.
- **Container lifetime:** each agent session runs its own container, labelled
  `io.github.ebirn.rea-container=mcp`, until the session exits. If the user asks about idle REA
  containers, list them with `podman ps --filter label=io.github.ebirn.rea-container=mcp`.
  Removing them disconnects every session still using one, this one included, so do it only on
  request. To avoid them, suggest enabling the plugin only in reverse-engineering projects
  (see the README section "Enable it only where you need it").

For the investigation workflow itself, follow the `reverse-engineer-anything` skill.
