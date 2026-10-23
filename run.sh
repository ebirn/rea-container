#!/bin/sh
# usage: ./run.sh <rea args...>  (hardened, offline; samples read-only, out writable)
cd "$(dirname "$0")" && exec podman run --rm --network=none --cap-drop=ALL \
  --security-opt no-new-privileges --read-only \
  --tmpfs /tmp:rw,size=1g --tmpfs /home/node:rw,size=512m,mode=1777 \
  -v ./samples:/samples:ro,Z -v ./out:/out:rw,Z rea-sandbox "$@"
