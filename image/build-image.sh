#!/bin/sh
set -eu

if test "$#" -ne 3; then
    printf 'usage: %s <resource-group> <gallery-name> <image-definition>\n' "$0" >&2
    exit 64
fi

resource_group=$1
gallery=$2
image_definition=$3

command -v az >/dev/null
command -v podman >/dev/null

# The image is built while connected, then generalized and versioned.
# Replace the temporary VM source below with the organization-approved image-builder lane.
az image builder create \
    --resource-group "$resource_group" \
    --name "${image_definition}-template" \
    --image-template image/template.json \
    --no-wait

printf 'Image Builder submission created for %s/%s/%s.\n' "$resource_group" "$gallery" "$image_definition"
printf 'Do not deploy tofu/ until the immutable gallery version contains Podman, nftables, and image/runtime.\n'
