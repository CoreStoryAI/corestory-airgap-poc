#!/bin/sh
set -eu

umask 077

bundle_dir=${1:-bundle}
plot_image=${PLOT_IMAGE:-localhost/plot-appliance:airgap}
llama_image=${LLAMA_IMAGE:-localhost/llama-server:airgap}
model_file=${MODEL_FILE:-models/default.gguf}

require_local_image() {
    image=$1
    if ! podman image exists "$image"; then
        printf 'Required local image is absent: %s\n' "$image" >&2
        printf 'Build or load it in the connected staging environment first.\n' >&2
        exit 66
    fi
}

require_local_image "$plot_image"
require_local_image "$llama_image"

if ! test -f "$model_file"; then
    printf 'Required local model is absent: %s\n' "$model_file" >&2
    exit 66
fi

rm -rf "$bundle_dir"
mkdir -p "$bundle_dir/images" "$bundle_dir/models"

podman save --format oci-archive --output "$bundle_dir/images/plot-appliance.tar" "$plot_image"
podman save --format oci-archive --output "$bundle_dir/images/llama-server.tar" "$llama_image"
install -m 0444 "$model_file" "$bundle_dir/models/default.gguf"

(
    cd "$bundle_dir"
    find images models -type f -print | LC_ALL=C sort | xargs sha256sum > SHA256SUMS
)

printf 'Offline bundle written to %s\n' "$bundle_dir"
