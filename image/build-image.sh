#!/bin/sh
set -eu

if test "$#" -ne 4; then
    printf 'usage: %s <profile> <resource-group> <gallery-name> <image-definition>\n' "$0" >&2
    exit 64
fi

profile=$1
resource_group=$2
gallery=$3
image_definition=$4
profile_file="image/profiles/${profile}.env"

case "$profile" in
    rhel9)
        expected_prepare_script=image/prepare-rhel9.sh
        ;;
    *)
        printf 'unsupported image profile: %s\n' "$profile" >&2
        exit 65
        ;;
esac

if ! test -f "$profile_file"; then
    printf 'image profile not found: %s\n' "$profile_file" >&2
    exit 66
fi

# The repository owns these profile files; do not source user-provided paths.
# shellcheck disable=SC1090
. "$profile_file"
: "${IMAGE_PUBLISHER:?profile must set IMAGE_PUBLISHER}"
: "${IMAGE_OFFER:?profile must set IMAGE_OFFER}"
: "${IMAGE_SKU:?profile must set IMAGE_SKU}"
: "${PREPARE_SCRIPT:?profile must set PREPARE_SCRIPT}"
if test "$PREPARE_SCRIPT" != "$expected_prepare_script"; then
    printf 'profile %s must use %s\n' "$profile" "$expected_prepare_script" >&2
    exit 65
fi

command -v az >/dev/null

# The image is built while connected, then generalized and versioned.
# The approved Image Builder template must stage image/runtime and the profile's
# preparation script before invoking it as root.
az image builder create \
    --resource-group "$resource_group" \
    --name "${image_definition}-template" \
    --image-template image/template.json \
    --no-wait

printf 'Image Builder submission created for %s/%s/%s with profile %s.\n' "$resource_group" "$gallery" "$image_definition" "$profile"
printf 'Source contract: %s:%s:%s:<pinned-version>; customizer: %s.\n' "$IMAGE_PUBLISHER" "$IMAGE_OFFER" "$IMAGE_SKU" "$PREPARE_SCRIPT"
printf 'Do not deploy terraform/ until the immutable gallery version contains Podman, nftables, and image/runtime.\n'
