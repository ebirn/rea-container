FROM docker.io/library/node:24-trixie

ARG REA_VERSION=6.7.0
ARG GHIDRA_URL=https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.2_build/ghidra_12.2_PUBLIC_20261016.zip

RUN apt-get update && apt-get install -y --no-install-recommends \
      openjdk-21-jdk-headless procps unzip curl ca-certificates \
      binwalk squashfs-tools p7zip-full file binutils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "$GHIDRA_URL" -o /tmp/ghidra.zip \
    && sha256sum /tmp/ghidra.zip \
    && unzip -q /tmp/ghidra.zip -d /opt && mv /opt/ghidra_* /opt/ghidra && rm /tmp/ghidra.zip

RUN npm install -g "rea-agents@${REA_VERSION}"

ENV GHIDRA_INSTALL_DIR=/opt/ghidra \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-arm64 \
    HOME=/home/node

USER node
WORKDIR /work
ENTRYPOINT ["rea"]
CMD ["mcp"]
