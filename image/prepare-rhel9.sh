#!/bin/sh
set -eu

if test "$(id -u)" -ne 0; then
    printf 'run as root on the connected RHEL 9 image build VM\n' >&2
    exit 77
fi

# shellcheck disable=SC1091
. /etc/os-release
if test "${ID:-}" != rhel || test "${VERSION_ID%%.*}" != 9; then
    printf 'this profile requires RHEL 9; found %s %s\n' "${ID:-unknown}" "${VERSION_ID:-unknown}" >&2
    exit 65
fi

payload_dir=${PLOT_AIRGAP_PAYLOAD_DIR:-/tmp/plot-airgap}
if ! test -x "$payload_dir/runtime/install.sh"; then
    printf 'runtime payload is missing from %s\n' "$payload_dir" >&2
    exit 66
fi

dnf -y install podman nftables curl coreutils util-linux policycoreutils

# The appliance ruleset is the only firewall owner in the baked runtime.
systemctl disable --now firewalld.service 2>/dev/null || true
systemctl mask firewalld.service
systemctl disable --now nftables.service 2>/dev/null || true
systemctl mask nftables.service

PLOT_AIRGAP_RUNTIME_DIR="$payload_dir/runtime" "$payload_dir/runtime/install.sh"
dnf clean all
rm -rf /var/cache/dnf
