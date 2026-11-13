#!/bin/sh
set -eu

if test "$(id -u)" -ne 0; then
    printf 'Run this importer as root.\n' >&2
    exit 77
fi

media=${1:-/media/airgap}
if ! findmnt --noheadings --output OPTIONS --target "$media" | tr ',' '\n' | grep -qx ro; then
    printf 'Offline media must be mounted read-only: %s\n' "$media" >&2
    exit 65
fi
cd "$media"
sha256sum -c SHA256SUMS

install -d -m 0755 /var/lib/plot/models /var/lib/plot/data /var/lib/plot/workspace
podman load --input images/plot-appliance.tar
podman load --input images/llama-server.tar
install -m 0444 models/default.gguf /var/lib/plot/models/default.gguf
restorecon -RF /var/lib/plot 2>/dev/null || true

systemctl daemon-reload
systemctl start llama.service
printf 'Images and model imported; Plot remains stopped and no corpus ingestion was started.\n'
