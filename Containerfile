# Multi-stage build: every tool is fetched or built in a throwaway stage and only the
# results are copied into a slim runtime image. Prebuilt upstream binaries are used
# wherever they exist; things with no binary (Binwalk 3, arm64 Rizin) are compiled.
# Works for linux/amd64 and linux/arm64 (TARGETARCH).

ARG NODE_IMAGE=docker.io/library/node:24-trixie-slim
ARG DEBIAN_IMAGE=docker.io/library/debian:trixie-slim
ARG RUST_IMAGE=docker.io/library/rust:1-slim-trixie
ARG DOTNET_SDK_IMAGE=mcr.microsoft.com/dotnet/sdk:10.0
ARG DOTNET_RUNTIME_IMAGE=mcr.microsoft.com/dotnet/runtime:10.0

# ---------------------------------------------------------------------------
# Verified downloads of prebuilt binaries (checksums pinned in SHA256SUMS)
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS fetch
ARG TARGETARCH
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
COPY SHA256SUMS /SHA256SUMS
# dl <name-in-SHA256SUMS> <url>: download to /dl/<name> and verify
RUN printf '%s\n' '#!/bin/sh' 'set -eu' 'mkdir -p /dl && cd /dl' \
      'curl -fsSL --retry 3 "$2" -o "$1"' \
      'grep "  $1\$" /SHA256SUMS | sha256sum -c -' > /usr/local/bin/dl \
 && chmod +x /usr/local/bin/dl \
 && mkdir -p /opt/rea /opt/bin

ARG GHIDRA_VERSION=12.1.4
RUN dl ghidra-${GHIDRA_VERSION}.zip \
      https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_20260921.zip \
 && unzip -q /dl/ghidra-*.zip -d /opt && mv /opt/ghidra_* /opt/ghidra && rm /dl/*

ARG JADX_MCP_VERSION=0.7.1
RUN dl jadx-headless-mcp-${JADX_MCP_VERSION}-all.jar \
      https://github.com/1013503897/jadx-headless-mcp/releases/download/v${JADX_MCP_VERSION}/jadx-headless-mcp-${JADX_MCP_VERSION}-all.jar \
 && mv /dl/*.jar /opt/rea/

ARG APKTOOL_VERSION=3.0.3
RUN dl apktool_${APKTOOL_VERSION}.jar \
      https://github.com/iBotPeaches/Apktool/releases/download/v${APKTOOL_VERSION}/apktool_${APKTOOL_VERSION}.jar \
 && mv /dl/apktool_*.jar /opt/rea/apktool.jar

ARG WABT_VERSION=1.0.42
RUN case "$TARGETARCH" in amd64) a=x64;; arm64) a=arm64;; esac \
 && dl wabt-${WABT_VERSION}-linux-$a.tar.gz \
      https://github.com/WebAssembly/wabt/releases/download/${WABT_VERSION}/wabt-${WABT_VERSION}-linux-$a.tar.gz \
 && mkdir /opt/wabt && tar -xzf /dl/wabt-*.tar.gz -C /opt/wabt --strip-components=1

ARG KUNA_VERSION=1.979
RUN case "$TARGETARCH" in amd64) a=x86_64;; arm64) a=arm64;; esac \
 && dl kuna-linux-$a.tar.gz \
      https://github.com/Noelo-Lab/kuna/releases/download/v${KUNA_VERSION}/kuna-v${KUNA_VERSION}-linux-$a.tar.gz \
 && mkdir /opt/kuna && tar -xzf /dl/kuna-linux-*.tar.gz -C /opt/kuna --strip-components=1 \
 && install -m755 /opt/kuna/kuna /opt/bin/kuna

ARG PWNDBG_VERSION=2026.09.15
RUN case "$TARGETARCH" in amd64) a=x86_64;; arm64) a=arm64;; esac \
 && dl pwndbg-$a.tar.xz \
      https://github.com/pwndbg/pwndbg/releases/download/${PWNDBG_VERSION}/pwndbg_${PWNDBG_VERSION}_$a-portable.tar.xz \
 && tar -xJf /dl/pwndbg-*.tar.xz -C /opt

ARG MITMPROXY_VERSION=12.2.3
RUN case "$TARGETARCH" in amd64) a=x86_64;; arm64) a=aarch64;; esac \
 && dl mitmproxy-linux-$a.tar.gz \
      https://downloads.mitmproxy.org/${MITMPROXY_VERSION}/mitmproxy-${MITMPROXY_VERSION}-linux-$a.tar.gz \
 && mkdir /opt/mitmproxy && tar -xzf /dl/mitmproxy-linux-*.tar.gz -C /opt/mitmproxy

ARG WAKARU_VERSION=1.14.0
RUN case "$TARGETARCH" in amd64) a=x64;; arm64) a=arm64;; esac \
 && npm install --prefix /opt/wakaru --no-audit --no-fund @wakaru/cli@${WAKARU_VERSION} \
 && install -m755 /opt/wakaru/node_modules/@wakaru/cli-linux-$a/wakaru /opt/bin/wakaru

# ---------------------------------------------------------------------------
# Ghidra's release zip only ships the native decompiler for x86_64; on arm64 it
# must be compiled from the matching source tag (needed for pseudocode output)
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS ghidra-decompiler
ARG TARGETARCH
ARG GHIDRA_VERSION=12.1.4
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates g++ make zlib1g-dev bison flex \
 && rm -rf /var/lib/apt/lists/*
ARG GHIDRA_COMMIT=8b6bbb857accdfa20dc5b2f5dea471178c2e9fbc
RUN mkdir -p /out && if [ "$TARGETARCH" = arm64 ]; then \
      git clone -q --depth 1 --filter=blob:none --sparse --branch "Ghidra_${GHIDRA_VERSION}_build" \
        https://github.com/NationalSecurityAgency/ghidra.git /src \
      && cd /src && git sparse-checkout set Ghidra/Features/Decompiler/src/decompile/cpp \
      && test "$(git rev-parse HEAD)" = "$GHIDRA_COMMIT" \
      && make -C Ghidra/Features/Decompiler/src/decompile/cpp -j"$(nproc)" ARCH_TYPE= ghidra_opt \
      && install -D -m755 Ghidra/Features/Decompiler/src/decompile/cpp/ghidra_opt /out/linux_arm_64/decompile; \
    fi

# ---------------------------------------------------------------------------
# Rizin: static prebuilt on amd64, compiled from the source tarball on arm64
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS rizin
ARG TARGETARCH
ARG RIZIN_VERSION=0.9.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates xz-utils \
 && rm -rf /var/lib/apt/lists/*
COPY SHA256SUMS /SHA256SUMS
RUN set -eu; mkdir -p /opt/rizin /src; \
    if [ "$TARGETARCH" = amd64 ]; then \
      curl -fsSL "https://github.com/rizinorg/rizin/releases/download/v${RIZIN_VERSION}/rizin-v${RIZIN_VERSION}-static-x86_64.tar.xz" -o /rz.tar.xz; \
      echo "$(grep ' rizin-static-x86_64.tar.xz$' /SHA256SUMS | cut -d' ' -f1)  /rz.tar.xz" | sha256sum -c -; \
      tar -xJf /rz.tar.xz -C /opt/rizin; \
    else \
      apt-get update; \
      apt-get install -y --no-install-recommends build-essential meson ninja-build pkg-config git python3; \
      curl -fsSL "https://github.com/rizinorg/rizin/releases/download/v${RIZIN_VERSION}/rizin-src-v${RIZIN_VERSION}.tar.xz" -o /rz.tar.xz; \
      echo "$(grep ' rizin-src.tar.xz$' /SHA256SUMS | cut -d' ' -f1)  /rz.tar.xz" | sha256sum -c -; \
      tar -xJf /rz.tar.xz -C /src --strip-components=1; \
      cd /src && meson setup build --prefix=/opt/rizin --buildtype=release -Dportable=true \
        && ninja -C build && ninja -C build install; \
    fi

# ---------------------------------------------------------------------------
# Binwalk 3.x (Rust) has no prebuilt release binaries; REA accepts 3.1.x only
# ---------------------------------------------------------------------------
FROM ${RUST_IMAGE} AS binwalk
ARG BINWALK_VERSION=3.1.0
RUN apt-get update \
 && apt-get install -y --no-install-recommends pkg-config libfontconfig1-dev libssl-dev cmake build-essential \
 && rm -rf /var/lib/apt/lists/*
RUN cargo install binwalk --version ${BINWALK_VERSION} --locked --root /opt/binwalk

# ---------------------------------------------------------------------------
# Python virtualenvs (pwntools for ELF/crash analysis, unblob for firmware)
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS pyenv
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv python3-dev build-essential \
      pkg-config libmagic1 \
 && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/venv-pwn \
 && /opt/venv-pwn/bin/pip install --no-cache-dir pwntools==4.15.0 pyelftools==0.33 unicorn==2.1.2
ARG UNBLOB_VERSION=26.6.4
RUN python3 -m venv /opt/venv-unblob \
 && /opt/venv-unblob/bin/pip install --no-cache-dir unblob==${UNBLOB_VERSION} jefferson ubi_reader

# ---------------------------------------------------------------------------
# ILSpy command line for .NET assemblies
# ---------------------------------------------------------------------------
FROM ${DOTNET_SDK_IMAGE} AS ilspy
RUN dotnet tool install ilspycmd --tool-path /opt/ilspycmd

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM ${DOTNET_RUNTIME_IMAGE} AS dotnet-runtime

FROM ${NODE_IMAGE} AS runtime
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      openjdk-21-jdk-headless procps util-linux ca-certificates file xz-utils \
      binutils gdb \
      tshark sigrok-cli sigrok-firmware-fx2lafw \
      adb \
      chromium fonts-liberation \
      python3 libmagic1 libfontconfig1 \
      p7zip-full squashfs-tools e2fsprogs lz4 zstd lzop cpio unar mtd-utils lziprecover \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s "$(dirname "$(dirname "$(readlink -f /usr/bin/javac)")")" /usr/lib/jvm/default

COPY --from=fetch    /opt/ghidra     /opt/ghidra
COPY --from=ghidra-decompiler /out/ /opt/ghidra/Ghidra/Features/Decompiler/os/
COPY --from=fetch    /opt/rea        /opt/rea
COPY --from=fetch    /opt/wabt       /opt/wabt
COPY --from=fetch    /opt/bin        /opt/bin
COPY --from=fetch    /opt/pwndbg     /opt/pwndbg
COPY --from=fetch    /opt/mitmproxy  /opt/mitmproxy
COPY --from=rizin    /opt/rizin      /opt/rizin
COPY --from=binwalk  /opt/binwalk    /opt/binwalk
COPY --from=pyenv    /opt/venv-pwn   /opt/venv-pwn
COPY --from=pyenv    /opt/venv-unblob /opt/venv-unblob
COPY --from=ilspy    /opt/ilspycmd   /opt/ilspycmd
COPY --from=dotnet-runtime /usr/share/dotnet /usr/share/dotnet

# Wrappers: apktool needs a launcher; Chromium needs --no-sandbox because the
# container (no capabilities, no network) is the sandbox.
RUN printf '#!/bin/sh\nexec java -jar /opt/rea/apktool.jar "$@"\n' > /usr/local/bin/apktool \
 && printf '#!/bin/sh\nexec /usr/bin/chromium --no-sandbox --disable-dev-shm-usage --disable-gpu "$@"\n' > /usr/local/bin/chromium-container \
 && chmod +x /usr/local/bin/apktool /usr/local/bin/chromium-container

ARG REA_VERSION=6.7.0
RUN npm install -g --no-audit --no-fund "rea-agents@${REA_VERSION}"

ENV PATH=/opt/rizin/bin:/opt/bin:/opt/wabt/bin:/opt/mitmproxy:$PATH \
    HOME=/home/node \
    JAVA_HOME=/usr/lib/jvm/default \
    DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
    GHIDRA_INSTALL_DIR=/opt/ghidra \
    REA_JADX_MCP_JAR=/opt/rea/jadx-headless-mcp-0.7.1-all.jar \
    REA_APKTOOL_COMMAND=/usr/local/bin/apktool \
    REA_WABT_BIN_DIRECTORY=/opt/wabt/bin \
    REA_BINWALK_COMMAND=/opt/binwalk/bin/binwalk \
    REA_UNBLOB_COMMAND=/opt/venv-unblob/bin/unblob \
    REA_FIRMWARE_PRLIMIT_COMMAND=/usr/bin/prlimit \
    REA_TSHARK_COMMAND=/usr/bin/tshark \
    REA_TSHARK_PRLIMIT_COMMAND=/usr/bin/prlimit \
    REA_SIGROK_COMMAND=/usr/bin/sigrok-cli \
    REA_SIGROK_PRLIMIT_COMMAND=/usr/bin/prlimit \
    REA_MITMDUMP_COMMAND=/opt/mitmproxy/mitmdump \
    REA_KUNA_COMMAND=/opt/bin/kuna \
    REA_WAKARU_COMMAND=/opt/bin/wakaru \
    REA_ILSPY_CMD_PATH=/opt/ilspycmd/ilspycmd \
    REA_ADB_PATH=/usr/bin/adb \
    REA_BROWSER_EXECUTABLE=/usr/local/bin/chromium-container \
    REA_PWNTOOLS_PYTHON=/opt/venv-pwn/bin/python \
    REA_PWNDBG_GDB=/opt/pwndbg/bin/gdb \
    REA_PWNDBG_GDBINIT=/opt/pwndbg/lib/python3.13/site-packages/pwndbginit/gdbinit.py \
    REA_PWNDBG_VENV_PATH=/opt/pwndbg

USER node
WORKDIR /work
ENTRYPOINT ["rea"]
CMD ["mcp"]
