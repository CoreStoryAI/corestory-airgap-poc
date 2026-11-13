#!/bin/sh
set -eu

failure=0

check_absent() {
    description=$1
    pattern=$2
    if ip -brief address 2>/dev/null | grep -Eq "$pattern"; then
        printf 'FAIL: %s\n' "$description"
        failure=1
    else
        printf 'PASS: %s\n' "$description"
    fi
}

check_absent "no globally scoped address" ' (UP|UNKNOWN) .* (inet6? )?([0-9a-f:]*:|[0-9]{1,3}\.)'

if ip route show default | grep -q .; then
    printf 'INFO: default route exists; NSG and host firewall must still reject it.\n'
else
    printf 'PASS: no default route\n'
fi

if nft list chain inet plot_airgap output | grep -q 'policy drop'; then
    printf 'PASS: host output policy drops by default\n'
else
    printf 'FAIL: host output policy is not drop\n'
    failure=1
fi

if curl --connect-timeout 3 --max-time 5 --silent --show-error https://example.com >/dev/null 2>&1; then
    printf 'FAIL: HTTPS egress succeeded\n'
    failure=1
else
    printf 'PASS: HTTPS egress probe failed as required\n'
fi

if getent ahosts example.com >/dev/null 2>&1; then
    printf 'FAIL: external DNS resolution succeeded\n'
    failure=1
else
    printf 'PASS: external DNS resolution failed as required\n'
fi

exit "$failure"
