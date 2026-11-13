#!/bin/sh
set -eu

install -d -m 0755 /etc/nftables /etc/containers/systemd /usr/local/sbin
install -m 0644 /tmp/plot-airgap/90-plot-airgap.nft /etc/nftables/90-plot-airgap.nft
install -m 0644 /tmp/plot-airgap/plot.container /etc/containers/systemd/plot.container
install -m 0644 /tmp/plot-airgap/llama.container /etc/containers/systemd/llama.container
install -m 0644 /tmp/plot-airgap/plot-airgap-firewall.service /etc/systemd/system/plot-airgap-firewall.service
install -m 0755 /tmp/plot-airgap/import-media.sh /usr/local/sbin/plot-import-media

systemctl enable plot-airgap-firewall.service
systemctl disable --now dnf-makecache.timer 2>/dev/null || true
systemctl disable --now packagekit.service 2>/dev/null || true
rm -rf /tmp/plot-airgap
